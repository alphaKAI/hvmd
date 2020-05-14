module hvmd.sexp;
import std.exception, std.string;

enum SexpObjectType {
  Float,
  Bool,
  String,
  Symbol,
  List,
  Object,
  Quote
}

class SexpObject {
  SexpObjectType type;
  union {
    double float_val;
    bool bool_val;
    string string_val;
    SexpObject[] list_val;
    SexpObject object_val;
  }

  private this(SexpObjectType type) {
    this.type = type;
  }

  this(double val) {
    this(SexpObjectType.Float);
    this.float_val = val;
  }

  this(bool val) {
    this(SexpObjectType.Bool);
    this.bool_val = val;
  }

  this(string val, SexpObjectType type) {
    this(type);
    this.string_val = val;
  }

  this(SexpObject[] val) {
    this(SexpObjectType.List);
    this.list_val = val;
  }

  this(SexpObject val, SexpObjectType type) {
    this(type);
    this.object_val = val;
  }

  double getDouble() {
    enforce(this.type == SexpObjectType.Float);
    return this.float_val;
  }

  bool getBool() {
    enforce(this.type == SexpObjectType.Bool);
    return this.bool_val;
  }

  string getSymbol() {
    enforce(this.type == SexpObjectType.Symbol);
    return this.string_val;
  }

  string getString() {
    enforce(this.type == SexpObjectType.String);
    return this.string_val;
  }

  SexpObject[] getList() {
    enforce(this.type == SexpObjectType.List);
    return this.list_val;
  }

  SexpObject getObject() {
    enforce(this.type == SexpObjectType.Object);
    return this.object_val;
  }

  SexpObject getQuote() {
    enforce(this.type == SexpObjectType.Quote);
    return this.object_val;
  }

  override string toString() {
    final switch (this.type) with (SexpObjectType) {
    case Float:
      return "%f".format(this.float_val);
    case Bool:
      return "%s".format(this.bool_val);
    case String:
      return "%s".format(this.string_val);
    case Symbol:
      return "%s".format(this.string_val);
    case List: {
        string[] elems;

        foreach (elem; this.list_val) {
          elems ~= elem.toString();
        }

        return "(%s)".format(elems.join(" "));

      }
    case Object: {
        return "(%s)".format(this.object_val);
      }
    case Quote: {
        return "'%s".format(this.object_val);
      }
    }
  }

  private this() {
  }

  SexpObject dup() {
    SexpObject that = new SexpObject();
    that.type = this.type;

    final switch (this.type) with (SexpObjectType) {
    case Float: {
        that.float_val = this.float_val;
        break;
      }
    case Bool: {
        that.bool_val = this.bool_val;
        break;
      }
    case String:
    case Symbol: {
        this.string_val = that.string_val;
        break;
      }
    case List: {
        SexpObject[] elems;

        foreach (elem; this.list_val) {
          elems ~= elem.dup;
        }
        that.list_val = elems;
        break;
      }
    case Object:
    case Quote: {
        that.object_val = this.object_val;
      }
    }

    return that;
  }
}
