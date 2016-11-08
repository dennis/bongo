
.PHONY: build_mx build_config all build

all: build

build: build_mx build_config

build_mx:
	sudo docker build -t bongo-mx bongo-mx

build_config:
	sudo docker build -t bongo-config bongo-config
