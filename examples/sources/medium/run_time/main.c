#include "IMPRESS_reconfiguration.h"

virtual_architecture_t va;

int main() {
	init_virtual_architecture();
	change_partition_position(&va, 0, 0, 40, 9);
	change_partition_position(&va, 0, 1, 40, 25);

	change_partition_element(&va, 0, 0, GROUP2_SHIFT1);
	change_partition_element(&va, 0, 1, GROUP1_ADD);
	change_partition_element(&va, 0, 0, GROUP2_SHIFT2);
	change_partition_element(&va, 0, 1, GROUP1_SUBSTRACT);
	while(1);

	return 0;
}
