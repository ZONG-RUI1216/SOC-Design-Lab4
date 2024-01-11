#include "fir.h"

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
	for(int i = 0; i < N; i = i + 1){
		inputbuffer[i] = 0;
		outputsignal[i] = 0;
	} 
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	//write down your fir
	for (int i = 0; i < N; i++) {
		for (int j = N-1; j > 0; j--) {
			inputbuffer[j] = inputbuffer[j - 1];
			outputsignal[i] += inputbuffer[j] * taps[j];
		}
		inputbuffer[0] = inputsignal[i];
		outputsignal[i] += inputbuffer[0] * taps[0];
	}
	
	return outputsignal;
	
}
	
	//riscv32-unknown-elf-gcc -I../../firmware -o counter_la_fir.elf ..
	//riscv32-unknown-elf-objcopy -O verilog counter_la_fir.elf counter_la_fir.hex
	//riscv32-unknown-elf-objdump -D counter_la_fir.elf > counter_la_fir.out
	
	/*for(int i = 0; i < N; i = i + 1){
		for(int j = 1; j < N; j = j + 1){
			inputbuffer[j] = inputbuffer[j - 1];
			outputsignal[i] += taps[N - j + 1]*inputbuffer[j];
		} 
		inputbuffer[0] = inputsignal[j];
		outputsignal[j] += taps[10]*inputbuffer[0];
	}
	*/
