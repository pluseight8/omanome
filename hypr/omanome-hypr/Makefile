SHELL := /usr/bin/env bash

TARGET := build/omanome-hypr.so
SOURCES := omanome-hypr.cpp wobbly-effect.cpp
CXX ?= g++
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++23 -Wall -Wextra -Wpedantic

ifeq ($(CXX),g++)
EXTRA_FLAGS := -fno-gnu-unique
else
EXTRA_FLAGS :=
endif

PKG_CFLAGS := $(shell pkg-config --cflags hyprland 2>/dev/null)
PKG_LIBS := $(shell pkg-config --libs hyprland 2>/dev/null)

.PHONY: all check check-deps clean test

all: check-deps $(TARGET)

check: test all

test: build/wobbly-physics-test
	@build/wobbly-physics-test
	@rm -f -- build/wobbly-physics-test

build/wobbly-physics-test: wobbly-physics-test.cpp wobbly-physics.hpp
	@mkdir -p build
	$(CXX) -O2 -std=c++23 -Wall -Wextra -Wpedantic wobbly-physics-test.cpp -o $@

check-deps:
	@command -v pkg-config >/dev/null 2>&1 || { echo 'omanome-hypr: pkg-config is required; install it with your normal package manager.' >&2; exit 2; }
	@pkg-config --exists hyprland || { echo 'omanome-hypr: matching Hyprland development headers are unavailable.' >&2; echo 'omanome-hypr: run hyprpm update or install the distribution development package manually.' >&2; exit 2; }

$(TARGET): $(SOURCES) wobbly-physics.hpp compatibility.json
	@mkdir -p build
	$(CXX) $(CXXFLAGS) $(EXTRA_FLAGS) $(PKG_CFLAGS) $(SOURCES) -o $@ $(PKG_LIBS)

clean:
	rm -rf build
