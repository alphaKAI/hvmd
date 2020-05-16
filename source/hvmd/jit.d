module hvmd.jit;
import hvmd.opcode, hvmd.vmvalue, hvmd.vmfunction, hvmd.util, hvmd.sexp;
import std.format;
import std.typecons;
import std.stdio;
import std.conv;

enum LABEL_PREFIX = "Label_";
enum CALL_PREFIX = "Call_";

private string genRuntimeCode() {
  return `#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <stdbool.h>

static inline double dmod(double x, double y) { return x - ((x / y) * y); }

static inline void* xmalloc(size_t size) {
  void *ptr = malloc(size);

  if (ptr == NULL) {
    fprintf(stderr, "Failed to allocate memory\n");
    exit(EXIT_FAILURE);
  }

  return ptr;
}
static inline void xfree(void *ptr) { free(ptr); }

typedef enum {
  Double
} CVMValueType;

typedef struct {
  CVMValueType type;
  union {
    double double_val;
  };
} CVMValue;

void enforce_CVMValueType(CVMValue *vmvalue, CVMValueType type) {
  assert(vmvalue->type == type);
}

CVMValue *new_CVMValue_Double(double x) {
  CVMValue *vmvalue = xmalloc(sizeof(CVMValue));

  vmvalue->type = Double;
  vmvalue->double_val = x;

  return vmvalue;
}

double get_CVMValue_Double(CVMValue *vmvalue) {
  enforce_CVMValueType(vmvalue, Double);
  return vmvalue->double_val;
}

CVMValue *dup_CVMValue(CVMValue *src) {
  CVMValue *dst = xmalloc(sizeof(CVMValue));

  dst->type = src->type;

  switch (src->type) {
    case Double: {
                   dst->double_val = src->double_val;
                   break;
                 }
    default: {
               fprintf(stderr, "Invalid type\n");
               exit(EXIT_FAILURE);
             }
  }

  return dst;
}

int cmp_CVMValue(CVMValue *lhs, CVMValue *rhs) {
  if (lhs->type != rhs->type) {
    return -1;
  }

  switch (lhs->type) {
    case Double: {
                   if (lhs->double_val < rhs->double_val) {
                     return -1;
                   } else if (lhs->double_val == rhs->double_val) {
                     return 0;
                   } else if (lhs->double_val > rhs->double_val) {
                     return 1;
                   }
                   break;
                 }
    default: {
               fprintf(stderr, "Invalid type\n");
               exit(EXIT_FAILURE);
             }
  }

  return -1;
}

bool eq_CVMValue(CVMValue *lhs, CVMValue *rhs) {
  return cmp_CVMValue(lhs, rhs) == 0;
}

void free_CVMValue(CVMValue *vmvalue) {
  xfree(vmvalue);
}

typedef struct {
  CVMValue **stack;
  size_t len;
  size_t capacity;
} Stack;

Stack *new_Stack(void) {
  Stack *stack = (Stack*)xmalloc(sizeof(Stack));
  stack->stack = (CVMValue**)xmalloc(sizeof(CVMValue*) * 16);
  stack->capacity = 16;
  stack->len = 0;
  return stack;
}

void free_Stack(Stack* stack) {
  xfree(stack->stack);
  xfree(stack);
}

void push_Stack(Stack *stack, CVMValue *val) {
  if (stack->len == stack->capacity) {
    stack->capacity *= 2;
    stack->stack = realloc(stack->stack, sizeof(double*) * stack->capacity);
  }

  stack->stack[stack->len++] = val;
}

void push_Stack_Double(Stack *stack, double val) {
  CVMValue *v = new_CVMValue_Double(val);
  push_Stack(stack, v);
}

CVMValue *pop_Stack(Stack *stack) {
  CVMValue *ret = stack->stack[--stack->len];
  return ret;
}

double pop_Stack_Double(Stack *stack) {
  CVMValue *popped = pop_Stack(stack);
  enforce_CVMValueType(popped, Double);
  return popped->double_val;
}

bool Stack_isempty(Stack *stack) {
  return stack->len == 0;
}

typedef struct {
  CVMValue **memory;
  CVMValue **args;
} Frame;

Frame new_Frame(void) {
  Frame frame;
  frame.memory = NULL;
  frame.args = NULL;
  return frame;
}

void free_Frame(Frame frame) {
  if (frame.args) {
    xfree(frame.args);
  }
}

typedef struct {
  Frame *stack;
  size_t len;
  size_t capacity;
} FStack;

FStack *new_FStack(void) {
  FStack *stack = (FStack*)xmalloc(sizeof(FStack));
  stack->stack = (Frame*)xmalloc(sizeof(Frame) * 16);
  stack->capacity = 16;
  stack->len = 0;
  return stack;
}

void free_FStack(FStack* stack) {
  assert(stack->len == 0);
  xfree(stack->stack);
  xfree(stack);
}

void push_FStack(FStack *stack, Frame val) {
  if (stack->len == stack->capacity) {
    stack->capacity *= 2;
    stack->stack = realloc(stack->stack, sizeof(Frame) * stack->capacity);
  }

  stack->stack[stack->len++] = val;
}

Frame pop_FStack(FStack *stack) {
  Frame ret = stack->stack[--stack->len];
  return ret;
}

typedef struct {
  void **stack;
  size_t len;
  size_t capacity;
} VStack;

VStack *new_VStack(void) {
  VStack *stack = (VStack*)xmalloc(sizeof(VStack));
  stack->stack = (void**)xmalloc(sizeof(void*) * 16);
  stack->capacity = 16;
  stack->len = 0;
  return stack;
}

void free_VStack(VStack* stack) {
  assert(stack->len == 0);
  xfree(stack->stack);
  xfree(stack);
}

void push_VStack(VStack *stack, void *val) {
  if (stack->len == stack->capacity) {
    stack->capacity *= 2;
    stack->stack = realloc(stack->stack, sizeof(void*) * stack->capacity);
  }

  stack->stack[stack->len++] = val;
}

void *pop_VStack(VStack *stack) {
  assert(stack->len > 0);
  void *ret = stack->stack[--stack->len];
  return ret;
}
`;
}

private string genOpsCode() {
  return `
#define AllocLvars(x) \
  do { \
    current_frame.memory = (CVMValue**)xmalloc(sizeof(CVMValue*) * x); \
  } while (0)
#define SetArgLocal(idx) \
  do { \
    current_frame.memory[idx] = current_frame.args[idx]; \
  } while(0)
#define GetLocal(idx) \
  do { \
    push_Stack(stack, current_frame.memory[idx]); \
  } while (0)
#define SetLocal(idx) \
  do { \
    current_frame.memory[idx] = pop_Stack(stack); \
  } while (0)
#define Label(label) \
  Label_##label:
#define Jump(label) \
  do { \
    goto Label_##label; \
  } while (0)

#define Branch(tBlock) \
  do { \
    if (pop_Stack_Double(stack) != 0.0) { \
      tBlock; \
    } \
  } while (0)

#define Pop \
  do { \
    pop_Stack(stack); \
  } while (0)

#define Push(val) \
  do { \
    push_Stack(stack, val); \
  } while (0)
#define Add \
  do { \
    double r = pop_Stack_Double(stack); \
    double l = pop_Stack_Double(stack); \
    push_Stack_Double(stack, l + r); \
  } while (0)
#define Sub \
  do { \
    double r = pop_Stack_Double(stack); \
    double l = pop_Stack_Double(stack); \
    push_Stack_Double(stack, l - r); \
  } while (0)
#define Mul \
  do { \
    double r = pop_Stack_Double(stack); \
    double l = pop_Stack_Double(stack); \
    push_Stack_Double(stack, l * r); \
  } while (0)
#define Div \
  do { \
    double r = pop_Stack(stack); \
    double l = pop_Stack(stack); \
    push_Stack(stack, l / r); \
  } while (0)
#define Mod \
  do { \
    double r = pop_Stack_Double(stack); \
    double l = pop_Stack_Double(stack); \
    push_Stack_Double(stack, dmod(l, r)); \
  } while (0)
#define Eq \
  do { \
    CVMValue *r = pop_Stack(stack); \
    CVMValue *l = pop_Stack(stack); \
    push_Stack_Double(stack, eq_CVMValue(l, r) ? 1.0 : 0.0); \
  } while (0)
#define Neq \
  do { \
    CVMValue *r = pop_Stack(stack); \
    CVMValue *l = pop_Stack(stack); \
    push_Stack_Double(stack, !eq_CVMValue(l, r) ? 1.0 : 0.0); \
  } while (0)
#define Lt \
  do { \
    CVMValue *r = pop_Stack(stack); \
    CVMValue *l = pop_Stack(stack); \
    push_Stack_Double(stack, cmp_CVMValue(l, r) == -1 ? 1.0 : 0.0); \
  } while (0)
#define Leq \
  do { \
    CVMValue *r = pop_Stack(stack); \
    CVMValue *l = pop_Stack(stack); \
    push_Stack_Double(stack, cmp_CVMValue(l, r) <= 0 ? 1.0 : 0.0); \
  } while (0)
#define Gt \
  do { \
    CVMValue *r = pop_Stack(stack); \
    CVMValue *l = pop_Stack(stack); \
    push_Stack_Double(stack, cmp_CVMValue(l, r) == 1 ? 1.0 : 0.0); \
  } while (0)
#define Geq \
  do { \
    CVMValue *r = pop_Stack(stack); \
    CVMValue *l = pop_Stack(stack); \
    push_Stack_Double(stack, cmp_CVMValue(l, r) >= 0? 1.0 : 0.0); \
  } while (0)
#define FreeLvars \
  do { \
    xfree(current_frame.memory); \
  } while (0)
#define Call(fid, argc, call_id) \
  push_FStack(fstack, current_frame); \
  current_frame = new_Frame(); \
  current_frame.args = (CVMValue**)xmalloc(sizeof(CVMValue*) * argc); \
  for (size_t i = 0; i < argc; i++) {\
    current_frame.args[i] = pop_Stack(stack); \
  }\
  push_VStack(vstack, &&CALL_ ##call_id); \
  goto FUNC_##fid; \
  CALL_##call_id:
#define Return \
  do { \
    free_Frame(current_frame); \
    current_frame = pop_FStack(fstack); \
    goto *pop_VStack(vstack); \
  } while(0)
#define DefFun(id) \
  FUNC_ ##id:
#define BuiltinCall(fname, argc) \
  do { \
    builtin_funcs[fname](stack, argc); \
  } while(0)
  `;
}

Opcode[string] builtin_functions;
static this() {
  builtin_functions = ["Print": opPrint, "Println": opPrintln];
}

static Opcode check_builtin(string name) {
  if (name in builtin_functions) {
    return builtin_functions[name];
  }
  else {
    return null;
  }
}

private string genBuiltinFunc() {
  return `
void builtin_Print(Stack *stack, int argc) {
  CVMValue **values = (CVMValue**)xmalloc(sizeof(CVMValue*) * argc);
  for (size_t i = 0; i < argc; i++) {
    values[argc - i - 1] = pop_Stack(stack);
  }
  for (size_t i = 0; argc > 0; argc--, i++) {
    switch (values[i]->type) {
      case Double: {
                     printf("%f", values[i]->double_val);
                     break;
                   }
    }
  }
}

void builtin_Println(Stack *stack, int argc) {
  CVMValue **values = (CVMValue**)xmalloc(sizeof(CVMValue*) * argc);
  for (size_t i = 0; i < argc; i++) {
    values[argc - i - 1] = pop_Stack(stack);
  }
  for (size_t i = 0; argc > 0; argc--, i++) {
    switch (values[i]->type) {
      case Double: {
                     printf("%f", values[i]->double_val);
                     break;
                   }
    }
  }
  printf("\n");
}

typedef void (*BUILTIN_FUNC)(Stack *stack, int argc);

enum {
  Print,
  Println
};

BUILTIN_FUNC builtin_funcs[] = {
  [Print] = &builtin_Print,
  [Println] = &builtin_Println
};
`;
}

private string genConstantPool(ContantPool constant_pool) {
  string double_constant_pool_code = `
#define DOUBLE_CONSTANT_POOL_SIZE %s
static CVMValue **DOUBLE_CONSTANT_POOL;

CVMValue *get_Double_from_Constant_Pool(size_t idx) {
  if (idx < DOUBLE_CONSTANT_POOL_SIZE) {
    return DOUBLE_CONSTANT_POOL[idx];
  } else {
    fprintf(stderr, "out of range\n");
    exit(EXIT_FAILURE);
  }
}`.format(constant_pool.double_pool.length);

  return double_constant_pool_code;
}

private string genInitCode(string name, ContantPool constant_pool) {
  string init_code = `
static bool %s_INITIALIZED = false;

void %s_init(void) {
  if (!%s_INITIALIZED) {`.format(name, name, name);

  init_code ~= `
    DOUBLE_CONSTANT_POOL = xmalloc(sizeof(CVMValue*) * DOUBLE_CONSTANT_POOL_SIZE);`;
  foreach (val; constant_pool.double_pool.keys) {
    size_t id = constant_pool.double_pool[val];
    init_code ~= `
    DOUBLE_CONSTANT_POOL[%s] = new_CVMValue_Double(%s);`.format(id, val);
  }

  init_code ~= `
    %s_INITIALIZED = true;
  }
}`;

  return init_code.format(name);
}

struct ContantPool {
  size_t[double] double_pool;
}

bool chmax(T)(ref T a, T b) {
  if (a < b) {
    a = b;
    return true;
  }
  else {
    return false;
  }
}

ContantPool calcContantPool(Opcode[] code) {
  ContantPool constant_pool;
  foreach (op; code) {
    switch (op.type) {
    case OpcodeType.OpPush: {
        SexpObject val = op.to!(OpPush).value.val;

        final switch (val.type) with (SexpObjectType) {
        case Double: {
            double double_val = val.double_val;
            if (double_val !in constant_pool.double_pool) {
              constant_pool.double_pool[double_val] = constant_pool.double_pool.length;
            }
            break;
          }
        case Bool:
        case String:
        case Symbol:
        case List:
        case Object:
        case Quote:
          break;
        }

        break;
      }
    default:
      break;
    }
  }

  return constant_pool;
}

size_t make_fresh_label() {
  static size_t _label;
  return _label++;
}

size_t make_fresh_call_id() {
  static size_t _call_id;
  return _call_id++;
}

private class OpCell {
  Opcode op;

  size_t dst_label;
  size_t[] labels;

  this(Opcode op) {
    this.op = op;
  }

  void addLabels(size_t label) {
    labels ~= label;
  }

  void setDstLabel(size_t dst_label) {
    this.dst_label = dst_label;
  }
}

/* TODO:
  Constant Poolを生成する。具体的には
  DoublePool: size_t[double] でIDを振る。
  IDをindexにConstantPoolを引くようにすればいい
*/
string CodeCompileToC(Opcode[] code, ContantPool constant_pool, size_t start_index = 0,
    Nullable!size_t opt_end_index = Nullable!(size_t).init,
    Nullable!(OpCell[]) calculated_cells = Nullable!(OpCell[]).init) {

  OpCell[] cells;

  // Resolve jumps
  if (calculated_cells.isNull) {
    cells.length = code.length;

    foreach (index, op; code) {
      cells[index] = new OpCell(op);
    }
    for (size_t index = start_index; index < cells.length; index++) {
      OpCell cell = cells[index];
      switch (cell.op.type) {
      case OpcodeType.OpJumpRel: {
          OpCell srcCell = cell;
          long offset = srcCell.op.to!(OpJumpRel).offset;
          size_t target_index = index + 1 + offset;
          OpCell targetCell = cells[target_index];
          size_t label = make_fresh_label();

          srcCell.setDstLabel(label);
          targetCell.addLabels(label);
          break;
        }
      default:
        break;
      }
    }
  }
  else {
    cells = calculated_cells.get;
  }

  // gen code
  string generated_code;
  string make_label(size_t label) {
    return "%s%s".format(LABEL_PREFIX, label);
  }

  void emitLabel(size_t label) {
    generated_code ~= "%s:\n".format(make_label(label));
  }

  void emitCode(string code) {
    generated_code ~= "%s;\n".format(code);
  }

  size_t argc;
  size_t end_index;
  if (opt_end_index.isNull) {
    end_index = cells.length;
  }
  else {
    end_index = opt_end_index.get;
  }

  for (size_t index = start_index; index < end_index;) {
    OpCell cell = cells[index++];

    foreach (label_id; cell.labels) {
      emitLabel(label_id);
    }

    Opcode op = cell.op;
  OP_SELECT:
    final switch (op.type) {
    case OpcodeType.OpPop:
      emitCode("Pop");
      break;
    case OpcodeType.OpPush: {
        SexpObject val = op.to!(OpPush).value.val;

        final switch (val.type) with (SexpObjectType) {
        case Double: {
            const double double_val = val.getDouble;
            size_t pool_idx = constant_pool.double_pool[double_val];
            emitCode("Push(get_Double_from_Constant_Pool(%s))".format(pool_idx));
            break;
          }
        case Bool:
        case String:
        case Symbol:
        case List:
        case Object:
        case Quote:
          unimplemented();
        }

        break;
      }
    case OpcodeType.OpAllocLvars:
      emitCode("AllocLvars(%d)".format(op.to!(OpAllocLvars).argc));
      break;
    case OpcodeType.OpFreeLvars:
      emitCode("FreeLvars");
      break;
    case OpcodeType.OpGetLocal:
      emitCode("GetLocal(%d)".format(op.to!(OpGetLocal).lvar_idx));
      break;
    case OpcodeType.OpSetLocal:
      emitCode("SetLocal(%d)".format(op.to!(OpSetLocal).lvar_idx));
      break;
    case OpcodeType.OpSetArgLocal:
      emitCode("SetArgLocal(%d)".format(op.to!(OpSetArgLocal).lvar_idx));
      break;
    case OpcodeType.OpAdd:
      emitCode("Add");
      break;
    case OpcodeType.OpSub:
      emitCode("Sub");
      break;
    case OpcodeType.OpMul:
      emitCode("Mul");
      break;
    case OpcodeType.OpDiv:
      emitCode("Div");
      break;
    case OpcodeType.OpMod:
      emitCode("Mod");
      break;
    case OpcodeType.OpEq:
      emitCode("Eq");
      break;
    case OpcodeType.OpNeq:
      emitCode("Neq");
      break;
    case OpcodeType.OpLt:
      emitCode("Lt");
      break;
    case OpcodeType.OpLeq:
      emitCode("Leq");
      break;
    case OpcodeType.OpGt:
      emitCode("Gt");
      break;
    case OpcodeType.OpGeq:
      emitCode("Geq");
      break;
    case OpcodeType.OpPrint:
      emitCode("CallBuiltin(Print, %d)".format(argc));
      break;
    case OpcodeType.OpPrintln:
      emitCode("CallBuiltin(Print, %d)".format(argc));
      break;
    case OpcodeType.OpJumpRel:
      emitCode("Jump(%s)".format(cell.dst_label));
      break;
    case OpcodeType.OpFuncDef: {
        VMFunction tvmf = op.to!(OpFuncDef).vm.func;
        emitCode("DefFun(%s)".format(tvmf.name));
        break;
      }
    case OpcodeType.OpCall: {
        OpCall op_call = op.to!(OpCall);
        string func_name = op_call.func_name;
        size_t func_argc = op_call.to!(OpCall).argc;

        Opcode maybe_builtin = check_builtin(func_name);
        if (maybe_builtin !is null) {
          op = maybe_builtin;
          argc = func_argc;
          goto OP_SELECT;
        }

        emitCode("Call(%s, %d, %d)".format(func_name, func_argc, make_fresh_call_id()));
        break;
      }
    case OpcodeType.OpReturn: {
        emitCode("Return");
        break;
      }
    case OpcodeType.OpVarDef: {
        unimplemented();
        break;
      }
    case OpcodeType.OpGetVar: {
        unimplemented();
        break;
      }
    case OpcodeType.OpSetVar: {
        unimplemented();
        break;
      }
    case OpcodeType.OpBranch: {
        size_t tBlock_len = op.to!(OpBranch).tBlock_len;

        string tBlock_code = CodeCompileToC(code, constant_pool, index,
            (index + tBlock_len).nullable, cells.nullable);
        emitCode("Branch({%s})".format(tBlock_code));
        index += tBlock_len;
        break;
      }
    case OpcodeType.OpDumpEnv: {
        unimplemented();
        break;
      }
    case OpcodeType.OpMakeList: {
        unimplemented();
        break;
      }
    case OpcodeType.OpSetArgFrom: {
        unimplemented();
        break;
      }
    }
  }

  return generated_code;
}

import hvmd.vmfunction;

Nullable!NativeFunction VMFunctionCompileToC(VMFunction vmf) {
  string ret_code;

  ContantPool constant_pool = calcContantPool(vmf.code);
  string func_body_code = CodeCompileToC(vmf.code, constant_pool);

  string generated_code = q{
CVMValue* %s(size_t argc, CVMValue **args) {
  %s_init();
  Frame current_frame = new_Frame();
  Stack *stack = new_Stack();
  FStack *fstack = new_FStack();
  VStack *vstack = new_VStack();

  // first time  
  current_frame.args = (CVMValue**)malloc(sizeof(CVMValue*) * argc);
  for (size_t i = 0; i < argc; i++) {
    current_frame.args[i] = args[i];
  }

  push_FStack(fstack, current_frame);
  push_VStack(vstack, &&Label_end);

FUNC_%s:
  %s

Label_end:
  free_FStack(fstack);
  free_VStack(vstack);

  if (!Stack_isempty(stack)) {
    CVMValue *v = pop_Stack(stack);
    free_Stack(stack);
    return v;
  } else {
    return 0;
  }
}
}.format(vmf.name, vmf.name, vmf.name, func_body_code);

  ret_code = `
%s
%s
%s
%s
%s
%s
`.format(genRuntimeCode, genBuiltinFunc, genOpsCode,
      genConstantPool(constant_pool), genInitCode(vmf.name, constant_pool), generated_code);

  const output_name = "%s_compiled.c".format(vmf.name);
  File(output_name, "w").writeln(ret_code);
  enum C_COMPILER = "clang";
  import std.process : executeShell;

  const dll_name = "lib%s.so".format(vmf.name);
  auto e = executeShell("%s -O3 -shared -o %s %s".format(C_COMPILER, dll_name, output_name));
  if (e.status != 0) {
    writeln("JIT Compile Failed");
    writeln(e.output);
    return typeof(return).init;
  }
  else {
    // currently for JIT; type of double is only supported.
    import hvmd.ffi, hvmd.sexp;

    SexpObjectType[] arg_types;
    SexpObjectType ret_type;

    foreach (_; 0 .. vmf.arg_names.length)
      arg_types ~= SexpObjectType.Double;

    ret_type = SexpObjectType.Double;

    return nullable(new NativeFunction(dll_name, vmf.name, arg_types, ret_type));
  }
}
