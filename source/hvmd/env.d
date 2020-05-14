module hvmd.env;
import hvmd.vmvalue;

enum FUNC_CACHE_LEN = 5;

class Env {
  VMValue[string] vars;
  Env parent;
  bool copied;
  VMValue[FUNC_CACHE_LEN] cached_functions;

  this(Env parent) {
    this.parent = parent;
  }

  this() {
    this(null);
  }

  VMValue get(string name) {
    for (Env e = this; e !is null; e = e.parent) {
      if (name in e.vars) {
        return e.vars[name];
      }
    }

    return null;
  }

  void set(string name, VMValue val) {
    this.vars[name] = val;
  }
  /*
  VMValue get(string name) {
    VMValue ret = check_cached(name);
    if (ret !is null) {
      return ret;
    }

    if (this.parent is null) {
      return this.vars[name];
    }
    else {
      if (this.copied == false) {
        for (Env e = this.parent; e !is null; e = e.parent) {
          if (name in e.vars) {
            return e.vars[name];
          }
        }
        return null;
      }
      else {
        return this.vars[name];
      }
    }
  }

  void set(string name, VMValue val) {
    if (this.parent !is null && this.copied == false) {
      string[] keys = this.parent.keys;
      for (size_t i = 0; i < keys.length; i++) {
        string key = keys[i];
        this.vars[key] = this.parent.get(key).dup;
      }
      this.copied = true;
    }

    this.vars[name] = val;
  }
  */

  string[] keys() {
    return this.vars.keys;
  }

  private VMValue check_cached(string name) {
    VMValue ret = null;

    foreach (vmv; this.cached_functions) {
      if (vmv is null) {
        continue;
      }
      if (vmv.func.name == name) {
        return vmv;
      }
    }

    return ret;
  }

  Env dup() {
    Env that = new Env(this);

    that.cached_functions = this.cached_functions;

    return that;
  }
}
