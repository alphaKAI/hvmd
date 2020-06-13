import std.stdio;
import std.format;
import hvmd.opcode, hvmd.util, hvmd.deserialize, hvmd.init, hvmd.exec;

enum CommandLineOptions {
	JIT_Enable = "--jit-enable",
	JIT_Disable = "--jit-disable",
	Quiet = "--quiet",
	Verbose = "--verbose",
	Execute = "-x",
	Dump = "-d"
}

void main(string[] args) {
	if (args.length < 3) {
		writefln("Usage: %s -x prog_path", args[0]);
	}
	args = args[1 .. $];

	bool verbose = true;
	bool JIT_ENABLED = true;

	// scan args
	string[] targs;

	foreach (arg; args) {
		switch (arg) {
		case CommandLineOptions.JIT_Enable: {
				JIT_ENABLED = true;
				break;
			}
		case CommandLineOptions.JIT_Disable: {
				JIT_ENABLED = false;
				break;
			}
		case CommandLineOptions.Quiet: {
				verbose = false;
				break;
			}
		case CommandLineOptions.Verbose: {
				verbose = true;
				break;
			}
		default: {
				targs ~= arg;
			}
		}
	}

	switch (targs[0]) {
	case CommandLineOptions.Execute: { //execute
			vm_init(JIT_ENABLED);

			long[] compiled_file = load_compiled_file(targs[1]);
			if (verbose) {
				writeln("compiled_file: ", compiled_file);
			}
			Opcode[] code = vm_deserialize(compiled_file);
			if (verbose) {
				vm_ins_dump(code);
			}
			vm_exec(code);
			break;
		}
	case CommandLineOptions.Dump: { //dump
			vm_init(JIT_ENABLED);

			long[] compiled_file = load_compiled_file(targs[1]);
			if (verbose) {
				writeln("compiled_file: ", compiled_file);
			}
			Opcode[] code = vm_deserialize(compiled_file);
			vm_ins_dump(code);
			break;
		}
	default: {
			throw new Error("Invalid Option: %s".format(args[0]));
		}
	}
}
