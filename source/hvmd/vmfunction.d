module hvmd.vmfunction;
import hvmd.opcode;
import std.format;
import std.conv;
import std.string;
import std.typecons;
import std.exception;
import std.stdio;
import core.memory;
import hvmd.ffi, hvmd.jit, hvmd.util;

bool JIT_ENABLED = true;

private {
  import hvmd.vmvalue;
  import hvmd.sexp;

  static Nullable!D_TYPE SexpObjectType_to_D_Type(SexpObjectType type) {
    final switch (type) with (SexpObjectType) {
    case Double:
      return D_TYPE.DOUBLE.nullable;
    case Bool:
      return D_TYPE.USHORT.nullable;
    case String:
    case Symbol:
      return D_TYPE.STRING.nullable;
    case List:
    case Object:
    case Quote:
      return typeof(return).init;
    }
  }

  static Nullable!D_TYPE VMValue_type_to_D_Type(VMValue value) {
    if (value.type == VMValueType.VFunc) { // func type is not supported
      return typeof(return).init;
    }
    else {
      SexpObject sexp = value.val;
      return SexpObjectType_to_D_Type(sexp.type);
    }
  }

  static void*[] VMValues_into_void_ptr_array(VMValue[] values) {
    void*[] ret;

    foreach (value; values) {
      if (VMValue_type_to_D_Type(value).isNull) { // check support
        throw new Exception("Unsupported type given");
      }

      SexpObject sexp = value.val;
      switch (sexp.type) with (SexpObjectType) {
      case Double: {
          ret ~= &sexp.double_val;
          break;
        }
      case Bool: {
          ret ~= &sexp.bool_val;
          break;
        }
      case String:
      case Symbol: {
          ret ~= &sexp.string_val;
          break;
        }
      default:
        break;
      }
    }

    return ret;
  }

  static bool checkCastable(T)(void* ptr) {
    return (cast(T*) ptr) !is null;
  }

  static void validate_ptr_type_D_Type(void* ptr, D_TYPE type) {
    final switch (type) with (D_TYPE) {
    case VOID:
      break;
    case UBYTE:
      if (!checkCastable!(ubyte)(ptr)) {
        throw new Error("Invalid argument<type error>");
      }
      break;
    case BYTE:
      if (!checkCastable!(byte)(ptr)) {
        throw new Error("Invalid argument<type error>");
      }
      break;
    case USHORT:
      if (!checkCastable!(ushort)(ptr)) {
        throw new Error("Invalid argument<type error>");
      }
      break;
    case SHORT:
      if (!checkCastable!(short)(ptr)) {
        throw new Error("Invalid argument<type error>");
      }
      break;
    case UINT:
      if (!checkCastable!(uint)(ptr)) {
        throw new Error("Invalid argument<type error>");
      }
      break;
    case INT:
      if (!checkCastable!(int)(ptr)) {
        throw new Error("Invalid argument<type error>");
      }
      break;
    case ULONG:
      if (!checkCastable!(ulong)(ptr)) {
        throw new Error("Invalid argument<type error>");
      }
      break;
    case LONG:
      if (!checkCastable!(long)(ptr)) {
        throw new Error("Invalid argument<type error>");
      }
      break;
    case FLOAT:
      if (!checkCastable!(float)(ptr)) {
        throw new Error("Invalid argument<type error>");
      }
      break;
    case DOUBLE:
      if (!checkCastable!(double)(ptr)) {
        throw new Error("Invalid argument<type error>");
      }
      break;
    case POINTER:
      if (!checkCastable!(void)(ptr)) {
        throw new Error("Invalid argument<type error>");
      }
      break;
    case STRING:
      if (!checkCastable!(char)(ptr)) {
        throw new Error("Invalid argument<type error>");
      }
      break;
    }
  }

  static CVMValue* ffi_arg_to_CVMValue(ffi_arg arg) {
    return cast(CVMValue*) arg;
  }

  static VMValue ffi_arg_to_VMValue(ffi_arg arg, SexpObjectType type) {
    switch (type) with (SexpObjectType) {
    case Double: {
        double val;
        import core.stdc.string;

        memcpy(&val, &arg, double.sizeof);
        return new VMValue(new SexpObject(val));
      }
    case Bool: {
        return new VMValue(new SexpObject(cast(bool) arg));
      }
    case String: {
        auto v = cast(char*) arg;
        return new VMValue(new SexpObject(cast(string) v.fromStringz, SexpObjectType.String));
      }
    case Symbol: {
        auto v = cast(char*) arg;
        return new VMValue(new SexpObject(cast(string) v.fromStringz, SexpObjectType.Symbol));
      }
    default:
      throw new Exception("Unsupported type specified");
    }
  }

  static VMValue CVMValue_to_VMValue(CVMValue* cvmvalue) {
    switch (cvmvalue.type) with (CVMValueType) {
    case Double: {
        return new VMValue(new SexpObject(cvmvalue.double_val));
      }
    case Bool: {
        return new VMValue(new SexpObject(cvmvalue.bool_val));
      }
    default:
      throw new Exception("Unsupported type specified");
    }
  }

  enum CVMValueType {
    Double,
    Bool
  }

  extern (C) {
    struct CVMValue {
      CVMValueType type;
      union {
        double double_val;
        bool bool_val;
      }
    }
  }

  CVMValue* VMValue_to_CVMValue(VMValue vmvalue) {
    if (vmvalue.type == VMValueType.VFunc) {
      unimplemented();
    }

    CVMValue* cvmvalue = cast(CVMValue*) GC.malloc(CVMValue.sizeof);
    SexpObject val = vmvalue.val;

    final switch (val.type) with (SexpObjectType) {
    case Double: {
        cvmvalue.type = CVMValueType.Double;
        cvmvalue.double_val = val.getDouble;
        break;
      }
    case Bool: {
        cvmvalue.type = CVMValueType.Bool;
        cvmvalue.bool_val = val.getBool;
        break;
      }
    case String:
    case Symbol:
    case List:
    case Object:
    case Quote:
      unimplemented();
    }

    return cvmvalue;
  }
}

class NativeFunctionArgument {
  size_t* argc;
  CVMValue** args;

  import core.memory;

  this(size_t argc, VMValue[] args) {
    this.argc = new size_t;
    *this.argc = argc;

    this.args = cast(CVMValue**) GC.malloc((CVMValue*).sizeof * args.length);
    foreach (i, ref arg; args) {
      this.args[i] = VMValue_to_CVMValue(arg);
    }
  }

  ~this() {
    GC.free(this.argc);
    GC.free(this.args);
  }
}

class NativeFunction {
  import core.sys.posix.dlfcn;

  // dll informations
  string dll_path;
  void* handle;

  // function informations
  string name;
  void* func_ptr;
  ffi_cif cif;

  this(string dll_path, string name) {
    this.dll_path = dll_path;
    this.name = name;

    // resolve dll
    {
      this.handle = dlopen(dll_path.toStringz, RTLD_LAZY);
      char* error = dlerror();

      if (error) {
        throw new Error("dlsym error: %s\n".format(error.fromStringz));
      }
    }

    // resolve function
    {
      this.func_ptr = dlsym(this.handle, name.toStringz);
      char* error = dlerror();

      if (error) {
        throw new Error("dlsym error: %s\n".format(error));
      }

      ffi_status status;

      import std.algorithm : map;
      import std.array : array;

      // FFI interface: CVMValue* fun(size_t, CVMValue* args)
      auto arg_d_types = [D_TYPE.ULONG, D_TYPE.POINTER];
      auto ret_d_type = D_TYPE.POINTER;

      auto _arg_types = d_types_to_ffi_types(arg_d_types);
      auto _r_type = d_type_to_ffi_type(ret_d_type);

      if ((status = ffi_prep_cif(&this.cif, ffi_abi.FFI_DEFAULT_ABI,
          _arg_types.length.to!uint, _r_type, cast(ffi_type**) _arg_types)) != ffi_status.FFI_OK) {
        throw new Error("ERROR : %d".format(status));
      }
    }
  }

  VMValue call(VMValue[] args) {
    NativeFunctionArgument nfa = new NativeFunctionArgument(args.length, args);

    ffi_arg result;
    void*[] real_ffi_args;
    real_ffi_args ~= nfa.argc;
    real_ffi_args ~= &nfa.args;

    ffi_call(&this.cif, this.func_ptr, &result, cast(void**) real_ffi_args);
    CVMValue* cvm_ret = ffi_arg_to_CVMValue(result);
    VMValue ret = CVMValue_to_VMValue(cvm_ret);
    return ret;
  }

  ~this() {
    dlclose(this.handle);
  }
}

class VMFunction {
  string name;
  Opcode[] code;
  string[] arg_names;

  Nullable!NativeFunction opt_native_func;
  bool jit_compile_tried;
  this(string name, Opcode[] code, string[] arg_names) {
    this.name = name;
    this.code = code;
    this.arg_names = arg_names;
  }

  override string toString() {
    string ret = "VMFunction<name: %s, arg_names: %s>\n".format(this.name, this.arg_names);

    foreach (c; code) {
      ret ~= c.toString() ~ "\n";
    }

    return ret;
  }

  private this() {
  }

  VMFunction dup() {
    VMFunction that = new VMFunction();
    that.name = this.name;
    that.arg_names = this.arg_names;
    foreach (c; this.code) {
      that.code ~= c.dup;
    }

    that.opt_native_func = this.opt_native_func;
    that.jit_compile_tried = this.jit_compile_tried;
    return that;
  }

  void jitCompile() {
    if (jit_compile_tried == false && JIT_ENABLED) {
      this.opt_native_func = VMFunctionCompileToC(this);
    }
    jit_compile_tried = true;
  }
}
