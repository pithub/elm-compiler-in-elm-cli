SHELL := /bin/sh

ELM := elm
ELMIE := ./elmie

SOURCES := $(shell find src compiler/src -type f -name '*.elm')
MAIN := src/Main.elm
OUTPUT := elm.js

.PHONY: all build run clean

all: run

$(OUTPUT): $(SOURCES)
	$(ELM) make $(MAIN) --output $(OUTPUT)

build: $(OUTPUT)

run: build
	@$(ELMIE) $(ARGS)

clean:
	rm -f $(OUTPUT)
