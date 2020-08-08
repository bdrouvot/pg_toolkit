PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

BIT_OBJS	= flip_bit_and_checksum.o

all: flip_bit_and_checksum.bin

flip_bit_and_checksum.bin: $(BIT_OBJS)
	$(CC) $^ -o $@

clean distclean maintainer-clean:
	rm -f flip_bit_and_checksum.bin $(BIT_OBJS) $(COMP_OBJS)
