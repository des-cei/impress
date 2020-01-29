#include "IMPRESS_reconfiguration.h"

virtual_architecture_t va;

int main() {
	init_virtual_architecture();
	change_partition_position(&va, 0, 0, 40, 9);

	change_partition_element(&va, 0, 0, ADD_RM);
	change_partition_element(&va, 0, 0, SUBSTRACT_RM);
	change_partition_element(&va, 0, 0, MULTIPLY_RM);
	while(1);

	return 0;
}
