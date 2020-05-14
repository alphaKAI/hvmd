module hvmd.exec;
import hvmd.sexp, hvmd.opcode, hvmd.vmvalue, hvmd.vmfunction, hvmd.frame, hvmd.registers;
import std.exception;
import std.format;
import std.conv;
import std.stdio;

static double dmod(double x, double y) {
  return x - ((x / y) * y);
}

enum DEFAULT_CAPACITY = 16;

class Stack(T) {
  size_t length;
  size_t capacity;

  T[] stack;

  this() {
    this(DEFAULT_CAPACITY);
  }

  this(size_t capacity) {
    this.length = capacity;
    this.capacity = capacity;
    this.stack.length = this.capacity;
  }

  void push(T val) {
    if (this.length == this.capacity) {
      this.capacity *= 2;
      this.stack.length = this.capacity;
    }

    stack[this.length++] = val;
  }

  T pop() {
    T ret = this.stack[--this.length];
    enum THRESHOOLD = 4;
    if (this.length == this.capacity / THRESHOOLD) {
      this.capacity = this.capacity / THRESHOOLD;
      this.stack.length = this.capacity;
    }

    return ret;
  }

  @property bool isEmpty() {
    return this.length == 0;
  }
}

SexpObject pop_SexpObject_from_stack(Stack!VMValue stack) {
  VMValue vmv = stack.pop();
  enforce(vmv.type == VMValueType.VValue);
  return vmv.val;
}

void push_Stack_VValue(Stack!VMValue stack, SexpObject sobj) {
  stack.push(new VMValue(sobj));
}

enum VM_EXEC_DEBUG = false;

Opcode[string] builtin_functions;

static this() {
  builtin_functions["print"] = opPrint();
  builtin_functions["println"] = opPrintln();
}

Opcode get_builtin(string name) {
  if (name in builtin_functions) {
    return builtin_functions[name];
  }
  else {
    return null;
  }
}

void vm_exec(Opcode[] code) {
  Stack!VMValue stack = new Stack!VMValue();
  Stack!Frame frame_stack = new Stack!Frame();
  Frame frame = new Frame();
  frame.v_ins = code;
  Registers reg = frame.registers;
  size_t bop_argc = 0;

  MAIN_LOOP: for (; reg.pc < frame.v_ins.length;) {
    Opcode op = frame.v_ins[reg.pc];
    static if (VM_EXEC_DEBUG) {
      writef("op: %s, reg: %s, reg.pc: %s\n", op, &reg, reg.pc);
      writeln("stack: ", stack.stack);
    }
  OP_SELECT:
    final switch (op.type) {

    case OpcodeType.OpPop: {
        stack.pop();
        reg.pc++;
      }
      break;
    case OpcodeType.OpPush: {
        stack.push(frame.v_ins[reg.pc++].to!(OpPush).value);
      }
      break;
    case OpcodeType.OpAllocLvars: {
        size_t vars = frame.v_ins[reg.pc++].to!(OpAllocLvars).argc;
        frame.lvars.length = vars;
      }
      break;
    case OpcodeType.OpFreeLvars: {
        frame.lvars.length = 0;
        reg.pc++;
      }
      break;
    case OpcodeType.OpGetLocal: {
        size_t var_idx = frame.v_ins[reg.pc++].to!(OpGetLocal).lvar_idx;
        stack.push(frame.lvars[var_idx]);
      }
      break;
    case OpcodeType.OpSetLocal: {
        size_t var_idx = frame.v_ins[reg.pc++].to!(OpSetLocal).lvar_idx;
        frame.lvars[var_idx] = stack.pop();
      }
      break;
    case OpcodeType.OpSetArgLocal: {
        size_t var_idx = frame.v_ins[reg.pc++].to!(OpSetArgLocal).lvar_idx;
        frame.lvars[var_idx] = frame.args[var_idx];
      }
      break;
    case OpcodeType.OpAdd: {
        double r = pop_SexpObject_from_stack(stack).getDouble();
        double l = pop_SexpObject_from_stack(stack).getDouble();
        push_Stack_VValue(stack, new SexpObject(l + r));
        reg.pc++;
      }
      break;
    case OpcodeType.OpSub: {
        double r = pop_SexpObject_from_stack(stack).getDouble();
        double l = pop_SexpObject_from_stack(stack).getDouble();
        push_Stack_VValue(stack, new SexpObject(l - r));
        reg.pc++;
      }
      break;
    case OpcodeType.OpMul: {
        double r = pop_SexpObject_from_stack(stack).getDouble();
        double l = pop_SexpObject_from_stack(stack).getDouble();
        push_Stack_VValue(stack, new SexpObject(l * r));
        reg.pc++;
      }
      break;
    case OpcodeType.OpDiv: {
        double r = pop_SexpObject_from_stack(stack).getDouble();
        double l = pop_SexpObject_from_stack(stack).getDouble();
        push_Stack_VValue(stack, new SexpObject(l / r));
        reg.pc++;
      }
      break;
    case OpcodeType.OpMod: {
        double r = pop_SexpObject_from_stack(stack).getDouble();
        double l = pop_SexpObject_from_stack(stack).getDouble();
        push_Stack_VValue(stack, new SexpObject(dmod(l, r)));
        reg.pc++;
      }
      break;
    case OpcodeType.OpEq: {
        VMValue r = stack.pop();
        VMValue l = stack.pop();
        push_Stack_VValue(stack, new SexpObject(cmp_VMValue(l, r) == 0));
        reg.pc++;
      }
      break;
    case OpcodeType.OpNeq: {
        VMValue r = stack.pop();
        VMValue l = stack.pop();
        push_Stack_VValue(stack, new SexpObject(cmp_VMValue(l, r) != 0));
        reg.pc++;
      }
      break;
    case OpcodeType.OpLt: {
        VMValue r = stack.pop();
        VMValue l = stack.pop();
        push_Stack_VValue(stack, new SexpObject(cmp_VMValue(l, r) < 0));
        reg.pc++;
      }
      break;
    case OpcodeType.OpLeq: {
        VMValue r = stack.pop();
        VMValue l = stack.pop();
        push_Stack_VValue(stack, new SexpObject(cmp_VMValue(l, r) <= 0));
        reg.pc++;
      }
      break;
    case OpcodeType.OpGt: {
        VMValue r = stack.pop();
        VMValue l = stack.pop();
        push_Stack_VValue(stack, new SexpObject(cmp_VMValue(l, r) > 0));
        reg.pc++;
      }
      break;
    case OpcodeType.OpGeq: {
        VMValue r = stack.pop();
        VMValue l = stack.pop();
        push_Stack_VValue(stack, new SexpObject(cmp_VMValue(l, r) >= 0));
        reg.pc++;
      }
      break;
    case OpcodeType.OpPrint: {
        VMValue[] values;
        values.length = bop_argc;
        for (size_t i = 0; i < bop_argc; i++) {
          values[bop_argc - i - 1] = stack.pop();
        }
        for (size_t i = 0; bop_argc > 0; bop_argc--, i++) {
          writef("%s", values[i]);
        }
      }
      break;
    case OpcodeType.OpPrintln: {
        VMValue[] values;
        values.length = bop_argc;
        for (size_t i = 0; i < bop_argc; i++) {
          values[bop_argc - i - 1] = stack.pop();
        }
        for (size_t i = 0; bop_argc > 0; bop_argc--, i++) {
          writef("%s", values[i]);
        }
        writeln();
      }
      break;
    case OpcodeType.OpJumpRel: {
        long lv = frame.v_ins[reg.pc++].to!(OpJumpRel).offset;
        reg.pc += lv;
      }
      break;
    case OpcodeType.OpFuncDef: {
        VMValue vm = frame.v_ins[reg.pc++].to!(OpFuncDef).vm;

        // Experimental
        /*
        import hvmd.jit;
        VMFunctionCompileToC(vm.func);
        */
        if (!vm.func.jit_compile_tried) {
          vm.func.jitCompile();
        }

        frame.env.set(vm.func.name, vm);
      }
      break;
    case OpcodeType.OpCall: {
        OpCall op_call = frame.v_ins[reg.pc++].to!(OpCall);
        string func_name = op_call.func_name;
        Opcode bop = get_builtin(func_name);
        if (bop !is null) {
          op = bop;
          bop_argc = op_call.argc;
          goto OP_SELECT;
        }

        VMValue v = frame.env.get(func_name);
        if (v is null) {
          throw new Error("No such a function : %s".format(func_name));
        }

        VMFunction vmf = get_func_VMValue(v);
        if (vmf.opt_native_func.isNull && !vmf.jit_compile_tried) {
          vmf.jitCompile();
        }

        size_t argc = op_call.argc;
        if (vmf.opt_native_func.isNull) {
          Frame new_frame = new Frame();
          new_frame.env = frame.env.dup;
          new_frame.parent = frame;

          new_frame.args.length = argc;
          for (size_t i = 0; i < argc; i++) {
            new_frame.args[i] = stack.pop();
          }

          new_frame.v_ins = vmf.code;
          frame_stack.push(frame);
          frame = new_frame;
          reg = new_frame.registers;
        }
        else {
          NativeFunction nfunc = vmf.opt_native_func.get;
          //writeln("Call nfunc: ", nfunc.name);
          VMValue[] args;
          args.length = argc;
          for (size_t i = 0; i < argc; i++) {
            args[i] = stack.pop();
          }
          stack.push(nfunc.call(args));
        }
      }
      break;
    case OpcodeType.OpReturn: {
        frame = frame_stack.pop();
        reg = frame.registers;
      }
      break;
    case OpcodeType.OpVarDef: {
        string var_name = frame.v_ins[reg.pc++].to!(OpVarDef).var_name;
        VMValue v = stack.pop();
        frame.env.set(var_name, v);
      }
      break;
    case OpcodeType.OpGetVar: {
        string var_name = frame.v_ins[reg.pc++].to!(OpGetVar).var_name;
        VMValue v = frame.env.get(var_name);
        stack.push(v);
      }
      break;
    case OpcodeType.OpSetVar: {
        string var_name = frame.v_ins[reg.pc++].to!(OpSetVar).var_name;
        VMValue v = stack.pop();
        frame.env.set(var_name, v);
      }
      break;
    case OpcodeType.OpBranch: {
        size_t tBlock_len = frame.v_ins[reg.pc++].to!(OpBranch).tBlock_len;
        SexpObject cond_result = pop_SexpObject_from_stack(stack);
        enforce(cond_result.type == SexpObjectType.Bool);

        if (!cond_result.bool_val) {
          reg.pc += tBlock_len;
        }
      }
      break;
    case OpcodeType.OpMakeList: {
        size_t list_len = frame.v_ins[reg.pc++].to!(OpMakeList).list_len;
        SexpObject[] list;
        list.length = list_len;

        for (size_t i = list_len; i > 0; i--) {
          list[i] = pop_SexpObject_from_stack(stack);
        }

        push_Stack_VValue(stack, new SexpObject(list));
      }
      break;
    case OpcodeType.OpSetArgFrom: {
        OpSetArgFrom opasf = frame.v_ins[reg.pc++].to!(OpSetArgFrom);
        string arg_name = opasf.arg_name;
        size_t arg_idx = opasf.arg_idx;
        enforce(arg_idx < frame.args.length);
        frame.env.set(arg_name, frame.args[arg_idx]);
      }
      break;
    case OpcodeType.OpDumpEnv: {
        string[] keys = frame.env.vars.keys;
        foreach (key; keys) {
          VMValue v = frame.env.get(key);
          writef("%s - %s\n", key, v.type == VMValueType.VValue ? "VValue" : "VFunc");
        }
      }
      break;

    }
  }

  // 戻るべきフレームが存在する．
  if (frame.parent !is null) {
    frame = frame_stack.pop();
    reg = frame.registers;
    goto MAIN_LOOP;
  }

}
