module hvmd.util;
import std.file;
import std.stdio;
import std.conv;
import std.exception;

long[] load_compiled_file(string file_name) {
  auto f = File(file_name, "r");
  FILE* fp = f.getFP();
  long[] ret;
  long val;

  while (fread(&val, long.sizeof, 1, fp) != 0) {
    ret ~= val;
  }

  f.close();

  return ret;
}

class Unimplemented : Error {
  this(string msg = "") {
    if (msg == "") {
      super("Unimplemented");
    }
    else {
      super("Unimplemented: " ~ msg);
    }
  }
}

void unimplemented(string msg = "") {
  throw new Unimplemented(msg);
}

import hvmd.opcode;

static void vm_ins_dump_impl(Opcode[] v_ins, size_t depth) {
  string sp;

  for (size_t i = 0; i < depth; i++) {
    sp ~= "  ";
  }

  for (size_t i = 0; i < v_ins.length;) {
    writef("%s[ins: %d] ", sp, i);
    Opcode op = v_ins[i];
    final switch (op.type) {
    case OpcodeType.OpPop:
      writef("OpPop\n");
      break;
    case OpcodeType.OpPush:
      writef("OpPush %s\n", v_ins[i++].to!(OpPush).value);
      break;
    case OpcodeType.OpAllocLvars:
      writef("OpAllocLvars %d\n", v_ins[i++].to!(OpAllocLvars).argc);
      break;
    case OpcodeType.OpFreeLvars:
      writef("%s\n", v_ins[i++]);
      break;
    case OpcodeType.OpGetLocal:
      writef("OpGetLocal %d\n", v_ins[i++].to!(OpGetLocal).lvar_idx);
      break;
    case OpcodeType.OpSetLocal:
      writef("OpSetLocal %d\n", v_ins[i++].to!(OpSetLocal).lvar_idx);
      break;
    case OpcodeType.OpSetArgLocal:
      writef("OpSetArgLocal %d\n",
          v_ins[i++].to!(OpSetArgLocal).lvar_idx);
      break;
    case OpcodeType.OpAdd:
    case OpcodeType.OpSub:
    case OpcodeType.OpMul:
    case OpcodeType.OpDiv:
    case OpcodeType.OpMod:
    case OpcodeType.OpEq:
    case OpcodeType.OpNeq:
    case OpcodeType.OpLt:
    case OpcodeType.OpLeq:
    case OpcodeType.OpGt:
    case OpcodeType.OpGeq:
    case OpcodeType.OpPrint:
    case OpcodeType.OpPrintln: {
        writef("%s\n", v_ins[i++]);
        break;
      }
    case OpcodeType.OpJumpRel: {
        writef("OpJumpRel %d\n", v_ins[i++].to!(OpJumpRel).offset);
        break;
      }
    case OpcodeType.OpFuncDef: {
        import hvmd.vmfunction;

        VMFunction vmf = v_ins[i++].to!(OpFuncDef).vm.func;
        writef("OpFuncDef %s\n", vmf.name);
        vm_ins_dump_impl(vmf.code, depth + 1);
        break;
      }
    case OpcodeType.OpCall: {
        OpCall op_call = v_ins[i++].to!(OpCall);
        string func_name = op_call.func_name;
        size_t argc = op_call.to!(OpCall).argc;
        writef("OpCall %s, %d\n", func_name, argc);
        break;
      }
    case OpcodeType.OpReturn: {
        writef("%s\n", v_ins[i++]);
        break;
      }
    case OpcodeType.OpVarDef: {
        string var_name = v_ins[i++].to!(OpVarDef).var_name;
        writef("OpVarDef %s\n", var_name);
        break;
      }
    case OpcodeType.OpGetVar: {
        string var_name = v_ins[i++].to!(OpGetVar).var_name;
        writef("OpGetVar %s\n", var_name);
        break;
      }
    case OpcodeType.OpSetVar: {
        string var_name = v_ins[i++].to!(OpSetVar).var_name;
        writef("OpSetVar %s\n", var_name);
        break;
      }
    case OpcodeType.OpBranch: {
        size_t tBlock_len = v_ins[i++].to!(OpBranch).tBlock_len;
        writef("OpBranch %d\n", tBlock_len);
        break;
      }
    case OpcodeType.OpDumpEnv: {
        writef("%s\n", v_ins[i++]);
        break;
      }
    case OpcodeType.OpMakeList: {
        size_t list_len = v_ins[i++].to!(OpMakeList).list_len;
        writef("OpMakeList %d\n", list_len);
        break;
      }
    case OpcodeType.OpSetArgFrom: {
        OpSetArgFrom opsaf = v_ins[i++].to!(OpSetArgFrom);
        string arg_name = opsaf.arg_name;
        size_t arg_idx = opsaf.arg_idx;
        writef("OpSetArgFrom %s %d\n", arg_name, arg_idx);
        break;
      }
    }
  }
}

void vm_ins_dump(Opcode[] v_ins) {
  vm_ins_dump_impl(v_ins, 0);
}
