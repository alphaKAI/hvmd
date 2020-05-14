module hvmd.init;
import hvmd.vmfunction;

void vm_init(bool JIT_ENABLED = true) {
  .JIT_ENABLED = JIT_ENABLED;
}
