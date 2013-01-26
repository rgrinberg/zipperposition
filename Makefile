
INTERFACE_FILES = $(shell find src -name '*.mli')
IMPLEMENTATION_FILES = $(shell find src -name '*.ml')
TARGET = zipperposition.native
LIBS = datalog,unix,str
SUBMODULES = datalog
PWD = $(shell pwd)
OPTIONS = -cflags -I,$(PWD)/datalog/_build/ -lflags -I,$(PWD)/datalog/_build/ -libs $(LIBS)

# switch compilation module
MODE = debug

all: $(MODE) tests

debug: $(SUBMODULES)
	ocamlbuild $(OPTIONS) -tag debug src/$(TARGET)

prod: $(SUBMODULES) tests
	ocamlbuild $(OPTIONS) -tag noassert src/$(TARGET)

profile: $(SUBMODULES) tests
	ocamlbuild $(OPTIONS) -tags debug,profile src/$(TARGET)

byte: $(SUBMODULES) tests
	ocamlbuild $(OPTIONS) -tags debug src/zipperposition.byte

tests: $(SUBMODULES)
	ocamlbuild $(OPTIONS) -tag debug -I src tests/tests.native

doc:
	ocamlbuild $(OPTIONS) src/zipperposition.docdir/index.html

clean:
	ocamlbuild -clean

tags:
	ctags $(IMPLEMENTATION_FILES) $(INTERFACE_FILES)

.PHONY: all profile clean tags doc tests

# libraries

datalog:
	make -C datalog

.PHONY: datalog
