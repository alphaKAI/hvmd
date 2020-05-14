module hvmd.frame;
import hvmd.registers, hvmd.env, hvmd.vmvalue, hvmd.opcode;

class Frame {
  Registers registers;
  Env env;
  VMValue[] args;
  Frame parent;
  VMValue[] lvars;
  Opcode[] v_ins;

  this(Frame parent) {
    this.parent = parent;
    this();
  }

  this() {
    this.registers = new Registers();
    this.env = new Env();
  }
}
