module hvmd.deserialize;
import std.conv, std.exception;
import hvmd.vmfunction, hvmd.vmvalue, hvmd.opcode, hvmd.sexp, hvmd.util;
import core.stdc.string : memcpy;

struct DeserializeStringResult {
  string str;
  size_t read_len;
}

static DeserializeStringResult deserialize_string(long[] serialized, size_t first_idx) {
  size_t idx = first_idx;
  size_t str_len = serialized[idx++];

  char[] buf = new char[str_len];
  for (size_t i = 0; i < str_len; i++) {
    buf[i] = serialized[idx++].to!char;
  }

  return DeserializeStringResult(buf.to!string, idx - first_idx);
}

struct DeserializeVMValueResult {
  VMValue vmvalue;
  size_t read_len;
}

static DeserializeVMValueResult deserialize_vmvalue(long[] serialized, size_t first_idx) {
  size_t idx = first_idx;
  VMValue ret;
  VMValueType ty = serialized[idx++].to!VMValueType;

  final switch (ty) with (VMValueType) {
  case VValue: {
      SexpObjectType obj_ty = serialized[idx++].to!SexpObjectType;
      final switch (obj_ty) with (SexpObjectType) {
      case Double: {
          long lv = serialized[idx++];
          double dv;
          memcpy(&dv, &lv, double.sizeof);

          ret = new VMValue(new SexpObject(dv));
          break;
        }
      case Bool: {
          unimplemented();
          break;
        }
      case String:
      case Symbol: {
          DeserializeStringResult dsr = deserialize_string(serialized, idx);
          idx += dsr.read_len;

          ret = new VMValue(new SexpObject(dsr.str, obj_ty));
          break;
        }
      case List:
        unimplemented();
        break;
      case Object:
        unimplemented();
        break;
      case Quote:
        unimplemented();
        break;
      }

      break;
    }
  case VFunc: {
      DeserializeStringResult dsr = deserialize_string(serialized, idx);
      idx += dsr.read_len;
      string func_name = dsr.str;

      long[] func_body_serialized;
      size_t code_len = serialized[idx++];
      for (size_t i = 0; i < code_len; i++) {
        func_body_serialized ~= serialized[idx++];
      }
      Opcode[] func_body = vm_deserialize(func_body_serialized);

      size_t arg_count = serialized[idx++].to!size_t;
      string[] args;
      for (size_t i = 0; i < arg_count; i++) {

        DeserializeStringResult arg_dsr = deserialize_string(serialized, idx);
        idx += arg_dsr.read_len;

        args ~= arg_dsr.str;
      }

      VMFunction vmf = new VMFunction(func_name, func_body, args);
      ret = new VMValue(vmf);
      break;
    }
  }

  return DeserializeVMValueResult(ret, idx - first_idx);
}

struct DeserializeStrIdxResult {
  string str;
  size_t idx;
  size_t read_len;
}

static DeserializeStrIdxResult deserialize_string_and_idx(long[] serialized, size_t first_idx) {
  size_t idx = first_idx;

  DeserializeStringResult dsr = deserialize_string(serialized, idx);
  idx += dsr.read_len;

  string name = dsr.str;
  size_t argc = serialized[idx++].to!size_t;

  return DeserializeStrIdxResult(name, argc, idx - first_idx);
}

Opcode[] vm_deserialize(long[] serialized) {
  Opcode[] code;

  for (size_t i = 0; i < serialized.length;) {
    OpcodeType op = serialized[i++].to!OpcodeType;

    final switch (op) with (OpcodeType) {
    case OpPop:
      code ~= opPop();
      break;
    case OpPush: {
        DeserializeVMValueResult result = deserialize_vmvalue(serialized, i);
        code ~= opPush(result.vmvalue);

        i += result.read_len;
        break;
      }
    case OpAllocLvars: {
        long lv = serialized[i++];
        code ~= opAllocLvars(lv);
        break;
      }
    case OpGetLocal: {
        long lv = serialized[i++];
        code ~= opGetLocal(lv);
        break;
      }
    case OpSetLocal: {
        long lv = serialized[i++];
        code ~= opSetLocal(lv);
        break;
      }
    case OpSetArgLocal: {
        long lv = serialized[i++];
        code ~= opSetArgLocal(lv);
        break;
      }
    case OpFreeLvars: {
        code ~= opFreeLvars();
        break;
      }
    case OpAdd: {
        code ~= opAdd();
        break;
      }
    case OpSub: {
        code ~= opSub();
        break;
      }
    case OpMul: {
        code ~= opMul();
        break;
      }
    case OpDiv: {
        code ~= opDiv();
        break;
      }
    case OpMod: {
        code ~= opMod();
        break;
      }
    case OpEq: {
        code ~= opEq();
        break;
      }
    case OpNeq: {
        code ~= opNeq();
        break;
      }
    case OpLt: {
        code ~= opLt();
        break;
      }
    case OpLeq: {
        code ~= opLeq();
        break;
      }
    case OpGt: {
        code ~= opGt();
        break;
      }
    case OpGeq: {
        code ~= opGeq();
        break;
      }
    case OpPrint: {
        code ~= opPrint();
        break;
      }
    case OpPrintln: {
        code ~= opPrintln();
        break;
      }
    case OpJumpRel: {
        long lv = serialized[i++];
        code ~= opJumpRel(lv);
        break;
      }
    case OpFuncDef: {
        DeserializeVMValueResult result = deserialize_vmvalue(serialized, i);
        VMValue vmv = result.vmvalue;

        enforce(vmv.type == VMValueType.VFunc);

        code ~= opFuncDef(vmv);

        i += result.read_len;
        break;
      }
    case OpCall: {
        DeserializeStrIdxResult result = deserialize_string_and_idx(serialized, i);
        code ~= opCall(result.str, result.idx);

        i += result.read_len;
        break;
      }
    case OpReturn: {
        code ~= opReturn();
        break;
      }
    case OpSetVar: {
        DeserializeStringResult dsr = deserialize_string(serialized, i);
        code ~= opSetVar(dsr.str);

        i += dsr.read_len;
        break;
      }
    case OpVarDef: {
        DeserializeStringResult dsr = deserialize_string(serialized, i);
        code ~= opVarDef(dsr.str);

        i += dsr.read_len;
        break;
      }
    case OpGetVar: {
        DeserializeStringResult dsr = deserialize_string(serialized, i);
        code ~= opGetVar(dsr.str);

        i += dsr.read_len;
        break;
      }
    case OpBranch: {
        size_t lv = serialized[i++].to!size_t;
        code ~= opBranch(lv);
        break;
      }
    case OpMakeList: {
        size_t lv = serialized[i++].to!size_t;
        code ~= opMakeList(lv);
        break;
      }
    case OpSetArgFrom: {
        DeserializeStrIdxResult result = deserialize_string_and_idx(serialized, i);
        code ~= opSetArgFrom(result.str, result.idx);
        i += result.read_len;
        break;
      }
    case OpDumpEnv: {
        code ~= opDumpEnv();
        break;
      }
    }
  }

  return code;
}
