#include "IMPRESS_reconfiguration.h"
#include <stdint.h>


virtual_architecture_t va;

int main() {
	uint32_t constant_value;

	init_virtual_architecture();
	change_partition_position(&va, 0, 1, 40, 25);
	change_partition_position(&va, 0, 0, 40, 9);

	change_partition_element(&va, 0, 1, MODULE_TOP);
	change_partition_element(&va, 0, 0, MODULE_BOTTOM);

	//Fine-grain reconfiguration
	change_partition_mux(&va, 0, 1, 0, 1);
	change_partition_mux(&va, 0, 1, 1, 0);
	constant_value = 5;
	change_partition_constant(&va, 0, 1, 0, &constant_value);
	constant_value = 6;
	change_partition_constant(&va, 0, 1, 1, &constant_value);
	change_partition_FU(&va, 0, 1, 0, add);
	constant_value = 5;
	change_partition_constant(&va, 0, 0, 0, &constant_value);
	change_partition_mux(&va, 0, 0, 0, 0);
	constant_value = 0x83;
	change_partition_constant(&va, 0, 0, 1, &constant_value);
	change_partition_FU(&va, 0, 0, 0, and);
	reconfigure_fine_grain();


	while(1);

	return 0;
}
