module hvmd.jit;
import hvmd.opcode, hvmd.vmvalue, hvmd.vmfunction, hvmd.util;
import std.format;
import std.typecons;
import std.stdio;
import std.conv;

enum LABEL_PREFIX = "Label_";
enum CALL_PREFIX = "Call_";

private string genRuntimeCode() {
  return `
#include <stdio.h>
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

typedef struct {
  double *stack;
  size_t len;
  size_t capacity;
} Stack;

Stack *new_Stack(void) {
  Stack *stack = (Stack*)xmalloc(sizeof(Stack));
  stack->stack = (double*)xmalloc(sizeof(double) * 16);
  stack->capacity = 16;
  stack->len = 0;
  return stack;
}

void free_Stack(Stack* stack) {
  xfree(stack->stack);
  xfree(stack);
}

void push_Stack(Stack *stack, double val) {
  if (stack->len == stack->capacity) {
    stack->capacity *= 2;
    stack->stack = realloc(stack->stack, sizeof(double*) * stack->capacity);
  }

  stack->stack[stack->len++] = val;
}

double pop_Stack(Stack *stack) {
  double ret = stack->stack[--stack->len];
  return ret;
}

bool Stack_isempty(Stack *stack) {
  return stack->len == 0;
}

typedef struct {
  double *memory;
  double *args;
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
    current_frame.memory = (double*)xmalloc(sizeof(double) * x); \
  } while (0)
#define SetArgLocal(idx) \
  do { \
    current_frame.memory[idx] = current_frame.args[idx]; \
  } while(0)
#define GetLocal(idx) \
  do { \
    push_Stack(stack, current_frame.memory[idx]); \
  } while (0)
#define Label(label) \
  Label_##label:
#define Jump(label) \
  do { \
    goto Label_##label; \
  } while (0)

#define Branch(tBlock) \
  do { \
    if (pop_Stack(stack) != 0.0) { \
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
    double r = pop_Stack(stack); \
    double l = pop_Stack(stack); \
    push_Stack(stack, l + r); \
  } while (0)
#define Sub \
  do { \
    double r = pop_Stack(stack); \
    double l = pop_Stack(stack); \
    push_Stack(stack, l - r); \
  } while (0)
#define Mul \
  do { \
    double r = pop_Stack(stack); \
    double l = pop_Stack(stack); \
    push_Stack(stack, l * r); \
  } while (0)
#define Div \
  do { \
    double r = pop_Stack(stack); \
    double l = pop_Stack(stack); \
    push_Stack(stack, l / r); \
  } while (0)
#define Mod \
  do { \
    double r = pop_Stack(stack); \
    double l = pop_Stack(stack); \
    push_Stack(stack, dmod(l, r)); \
  } while (0)
#define Eq \
  do { \
    double r = pop_Stack(stack); \
    double l = pop_Stack(stack); \
    push_Stack(stack, l == r ? 1.0 : 0.0); \
  } while (0)
#define Neq \
  do { \
    double r = pop_Stack(stack); \
    double l = pop_Stack(stack); \
    push_Stack(stack, l != r ? 1.0 : 0.0); \
  } while (0)
#define Lt \
  do { \
    double r = pop_Stack(stack); \
    double l = pop_Stack(stack); \
    push_Stack(stack, l < r ? 1.0 : 0.0); \
  } while (0)
#define Leq \
  do { \
    double r = pop_Stack(stack); \
    double l = pop_Stack(stack); \
    push_Stack(stack, l <= r ? 1.0 : 0.0); \
  } while (0)
#define Gt \
  do { \
    double r = pop_Stack(stack); \
    double l = pop_Stack(stack); \
    push_Stack(stack, l > r ? 1.0 : 0.0); \
  } while (0)
#define Geq \
  do { \
    double r = pop_Stack(stack); \
    double l = pop_Stack(stack); \
    push_Stack(stack, l >= r ? 1.0 : 0.0); \
  } while (0)
#define FreeLvars \
  do { \
    xfree(current_frame.memory); \
  } while (0)
#define Call(fid, argc, call_id) \
    push_FStack(fstack, current_frame); \
    current_frame = new_Frame(); \
    current_frame.args = (double*)xmalloc(sizeof(double) * argc); \
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
  double *values = (double*)xmalloc(sizeof(double) * argc);
  for (size_t i = 0; i < argc; i++) {
    values[argc - i - 1] = pop_Stack(stack);
  }
  for (size_t i = 0; argc > 0; argc--, i++) {
    printf("%f", values[i]);
  }
}
void builtin_Println(Stack *stack, int argc) {
  double *values = (double*)xmalloc(sizeof(double) * argc);
  for (size_t i = 0; i < argc; i++) {
    values[argc - i - 1] = pop_Stack(stack);
  }
  for (size_t i = 0; argc > 0; argc--, i++) {
    printf("%f", values[i]);
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

string CodeCompileToC(Opcode[] code, size_t start_index = 0,
    Nullable!size_t opt_end_index = Nullable!(size_t).init, bool need_jump_resolve = true) {
  class OpCell {
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

  size_t make_fresh_label() {
    static size_t _label;
    return _label++;
  }

  size_t make_fresh_call_id() {
    static size_t _call_id;
    return _call_id++;
  }

  OpCell[] cells;
  cells.length = code.length;

  foreach (index, op; code) {
    cells[index] = new OpCell(op);
  }

  // Resolve jumps
  if (need_jump_resolve) {
    for (size_t index = start_index; index < cells.length; index++) {
      OpCell cell = cells[index];
      switch (cell.op.type) {
      case OpcodeType.OpJumpRel: {
          OpCell srcCell = cell;
          long offset = srcCell.op.to!(OpJumpRel).offset;
          OpCell targetCell = cells[index + 1 + offset];
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
    case OpcodeType.OpPush:
      emitCode("Push(%s)".format(op.to!(OpPush).value.val.getDouble));
      break;
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

        string tBlock_code = CodeCompileToC(code, index, (index + tBlock_len).nullable, false);
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

  string func_body_code = CodeCompileToC(vmf.code);

  string generated_code = q{
double %s(size_t argc, double *args) {
  Frame current_frame = new_Frame();
  Stack *stack = new_Stack();
  FStack *fstack = new_FStack();
  VStack *vstack = new_VStack();

  // first time  
  current_frame.args = (double*)malloc(sizeof(double) * argc);
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
    double v = pop_Stack(stack);
    free_Stack(stack);
    return v;
  } else {
    return 0;
  }
}
}.format(vmf.name, vmf.name, func_body_code);

  ret_code = `
%s
%s
%s
%s
`.format(genRuntimeCode, genBuiltinFunc, genOpsCode, generated_code);

  const output_name = "%s_compiled.c".format(vmf.name);
  File(output_name, "w").writeln(ret_code);
  enum C_COMPILER = "clang";
  import std.process : executeShell;

  const dll_name = "lib%s.so".format(vmf.name);
  auto e = executeShell("%s -shared -o %s %s".format(C_COMPILER, dll_name, output_name));
  if (e.status != 0) {
    return typeof(return).init;
  }
  else {
    // currently for JIT; type of double is only supported.
    import hvmd.ffi, hvmd.sexp;

    SexpObjectType[] arg_types;
    SexpObjectType ret_type;

    foreach (_; 0 .. vmf.arg_names.length)
      arg_types ~= SexpObjectType.Float;

    ret_type = SexpObjectType.Float;

    return nullable(new NativeFunction(dll_name, vmf.name, arg_types, ret_type));
  }
}
