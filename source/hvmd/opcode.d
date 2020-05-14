module hvmd.opcode;
import std.typecons;
import std.string;
import std.format;
import hvmd.vmvalue;
import hvmd.vmfunction;

enum OpcodeType {
  OpPop,
  OpPush,
  OpAllocLvars,
  OpFreeLvars,
  OpGetLocal,
  OpSetLocal,
  OpSetArgLocal,
  OpAdd,
  OpSub,
  OpMul,
  OpDiv,
  OpMod,
  OpEq,
  OpNeq,
  OpLt,
  OpLeq,
  OpGt,
  OpGeq,
  OpPrint,
  OpPrintln,
  OpJumpRel,
  OpFuncDef,
  OpCall,
  OpReturn,
  OpVarDef,
  OpGetVar,
  OpSetVar,
  OpBranch,
  OpMakeList,
  OpSetArgFrom,
  OpDumpEnv
}

interface Opcode {
  OpcodeType type();
  Opcode dup();
  string toString();
}

string defOpcode(string name, Tuple!(string, string)[] members = [])() {
  string code;

  code ~= "class Op%s : Opcode {".format(name);

  code ~= `
  OpcodeType type() {
    return OpcodeType.Op%s;
  }
`.format(name);

  foreach (member; members) {
    code ~= "  %s %s;".format(member[0], member[1]);
  }

  string[] constructor_args;
  string[] intialize_codes;
  string[] member_names;
  foreach (member; members) {
    string member_type = member[0];
    string member_name = member[1];

    constructor_args ~= "%s %s".format(member_type, member_name);
    intialize_codes ~= "this.%s = %s;".format(member_name, member_name);

    member_names ~= member_name;
  }

  code ~= `
  this (%s) {
    %s
  }
`.format(constructor_args.join(", "), intialize_codes.join("\n"));

  enum RITCH_PRINT = false;

  static if (RITCH_PRINT) {
    if (member_names.length) {
      string fmt = ({
        string[] ret;
        foreach (_; 0 .. member_names.length) {
          ret ~= "%s";
        }
        return ret.join(", ");
      })();

      code ~= `
  override string toString() {
    return "Op%s: %s".format(%s);
  }
`.format(name, fmt, member_names.join(", "));
    }
    else {
      code ~= `
  override string toString() {
    return "Op%s";
  }
`.format(name);
    }
  }
  else {
    code ~= `
  override string toString() {
    return "Op%s";
  }
`.format(name);
  }

  if (member_names.length) {
    code ~= `
  private this() {}
`;
  }
  code ~= `
  Opcode dup() {
    return new Op%s(%s);
  }
`.format(name, member_names.length ? member_names.join(".dup, ") : "");

  code ~= "}";
  code ~= `
Opcode op%s(%s) {
   return new Op%s(%s);
}
`.format(name, constructor_args.join(", "), name, member_names.join(", "));

  return code;
}

size_t dup(size_t v) {
  return v;
}

string dup(string v) {
  return v;
}

long dup(long v) {
  return v;
}

mixin(defOpcode!("Pop"));
mixin(defOpcode!("Push", [tuple("VMValue", "value")]));
mixin(defOpcode!("AllocLvars", [tuple("size_t", "argc")]));
mixin(defOpcode!("FreeLvars"));
mixin(defOpcode!("GetLocal", [tuple("size_t", "lvar_idx")]));
mixin(defOpcode!("SetLocal", [tuple("size_t", "lvar_idx")]));
mixin(defOpcode!("SetArgLocal", [tuple("size_t", "lvar_idx")]));
mixin(defOpcode!("Add"));
mixin(defOpcode!("Sub"));
mixin(defOpcode!("Mul"));
mixin(defOpcode!("Div"));
mixin(defOpcode!("Mod"));
mixin(defOpcode!("Eq"));
mixin(defOpcode!("Neq"));
mixin(defOpcode!("Lt"));
mixin(defOpcode!("Leq"));
mixin(defOpcode!("Gt"));
mixin(defOpcode!("Geq"));
mixin(defOpcode!("Print"));
mixin(defOpcode!("Println"));
mixin(defOpcode!("JumpRel", [tuple("long", "offset")]));
mixin(defOpcode!("FuncDef", [tuple("VMValue", "vm")]));
mixin(defOpcode!("Call", [tuple("string", "func_name"), tuple("size_t", "argc")]));
mixin(defOpcode!("Return"));
mixin(defOpcode!("VarDef", [tuple("string", "var_name")]));
mixin(defOpcode!("GetVar", [tuple("string", "var_name")]));
mixin(defOpcode!("SetVar", [tuple("string", "var_name")]));
mixin(defOpcode!("Branch", [tuple("size_t", "tBlock_len")]));
mixin(defOpcode!("MakeList", [tuple("size_t", "list_len")]));
mixin(defOpcode!("SetArgFrom", [
      tuple("string", "arg_name"), tuple("size_t", "arg_idx")
    ]));
mixin(defOpcode!("DumpEnv"));
