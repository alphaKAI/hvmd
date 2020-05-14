module hvmd.vmvalue;
import hvmd.sexp, hvmd.vmfunction, hvmd.util;
import std.format;
import std.exception;

enum VMValueType {
  VValue,
  VFunc
}

class VMValue {
  VMValueType type;
  union {
    SexpObject val;
    VMFunction func;
  }

  this(SexpObject val) {
    this.type = VMValueType.VValue;
    this.val = val;
  }

  this(VMFunction func) {
    this.type = VMValueType.VFunc;
    this.func = func;
  }

  override string toString() {
    return this.type == VMValueType.VValue ? this.val.toString : this.func.toString;
  }

  VMValue dup() {
    final switch (this.type) with (VMValueType) {
    case VValue:
      return new VMValue(this.val.dup);
    case VFunc:
      return new VMValue(this.func.dup);
    }
  }
}

int cmp_VMValue(VMValue v1, VMValue v2) {
  if (v1.type != v2.type) {
    return -2;
  }
  final switch (v1.type) with (VMValueType) {
  case VValue: {
      final switch (v1.val.type) with (SexpObjectType) {
      case Float: {
          double l = v1.val.getDouble;
          double r = v2.val.getDouble;
          if (l == r) {
            return 0;
          }
          if (l < r) {
            return -1;
          }
          return 1;
        }
      case Bool: {
          bool l = v1.val.getBool;
          bool r = v2.val.getBool;
          if (l == r) {
            return 0;
          }
          return -2;
        }
      case Symbol:
      case String:
        int varcmp(string s1, string s2) {
          if (s1 == s2) {
            return 0;
          }
          if (s1 < s2) {
            return -1;
          }
          return 1;
        }

        return varcmp(v1.val.string_val, v2.val.string_val);
      case List:
      case Object:
      case Quote:
        unimplemented;
      }
    }
    break;
  case VFunc:
    throw new Error("Should not reach here\n");
  }
  throw new Error("Should not reach here\n");
}

VMFunction get_func_VMValue(VMValue vmv) {
  enforce(vmv.type == VMValueType.VFunc);
  return vmv.func;
}
