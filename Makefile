.PHONY : dockerfy dist-clean dist release zombie-maker

TAG  := $(shell git describe --tags --match '[0-9]*\.[0-9]*')
YTAG := $(shell echo $(TAG) | cut -d. -f1,2)
XTAG := $(shell echo $(TAG) | cut -d. -f1)
LDFLAGS:=-X main.buildVersion=$(TAG)
DOLLAR='$'
export SHELL = /bin/bash

all: dockerfy nginx-with-dockerfy


prereqs: .mk.glide


.mk.glide: glide.yaml
	glide --no-color install -u -s -v
	touch .mk.glide


fmt:
	@echo gofmt:
	@test -z `glide novendor -x | sed '$$d' | xargs gofmt -l | tee /dev/stderr` && echo passed
	@echo


lint:
	@{ \
		if [ -z `which golint` ]; then \
			echo "golint not found in path. Available from: github.com/golang/lint/golint" ;\
			exit 1 ;\
		fi ;\
	}
	@echo golint:
	@glide novendor | xargs -n1 golint
	@echo

is-open-source-clean:
	@{ \
		if glide -q list 2>/dev/null | egrep -iq 'github.com/SocialCodeInc'; then \
			echo "Dockerfy is OPEN SOURCE -- no dependencies on SocialCodeInc sources are allowed"; \
		else \
			echo "Dockerfy is clean for OPEN SOURCE"; \
		fi; \
	}

dockerfy: prereqs *.go
	echo "Building dockerfy"
	go build -ldflags '$(LDFLAGS)'


debug: prereqs
	godebug run  $(ls *.go | egrep -v unix)


dist-clean:
	rm -rf dist
	rm -f dockerfy-linux-*.tar.gz


dist: dist-clean dist/linux/amd64/dockerfy nginx-with-dockerfy


# NOTE: this target is built by the above ^^ amd64 make inside a golang docker container
dist/linux/amd64/dockerfy: prereqs Makefile *.go
	mkdir -p dist/linux/amd64
	@# a native build allows user.Lookup to work.  Not sure why it doesn't if we cross-compile
	@# from OSX
	docker run --rm  \
	  --volume $$PWD/vendor:/go/src  \
	  --volume $$PWD:/go/src/dockerfy \
	  --workdir /go/src/dockerfy \
	  golang:1.7 go build -ldflags "$(LDFLAGS)" -o dist/linux/amd64/dockerfy


release: dist
	mkdir -p dist/release
	tar -czf dist/release/dockerfy-linux-amd64-$(TAG).tar.gz -C dist/linux/amd64 dockerfy
	@#tar -czf dist/release/dockerfy-linux-armel-$(TAG).tar.gz -C dist/linux/armel dockerfy
	@#tar -czf dist/release/dockerfy-linux-armhf-$(TAG).tar.gz -C dist/linux/armhf dockerfy


nginx-with-dockerfy:  dist/.mk.nginx-with-dockerfy


dist/.mk.nginx-with-dockerfy: Makefile dist/linux/amd64/dockerfy Dockerfile.nginx-with-dockerfy
	docker build -t socialcode/nginx-with-dockerfy:$(TAG) --file Dockerfile.nginx-with-dockerfy .
	docker tag socialcode/nginx-with-dockerfy:$(TAG) nginx-with-dockerfy
	touch dist/.mk.nginx-with-dockerfy


float-tags: nginx-with-dockerfy
	# fail if we're not on a pure Z tag
	git describe --tags | egrep -q '^[0-9\.]+$$'
	docker tag socialcode/nginx-with-dockerfy:$(TAG) socialcode/nginx-with-dockerfy:$(YTAG)
	docker tag socialcode/nginx-with-dockerfy:$(TAG) socialcode/nginx-with-dockerfy:$(XTAG)

push: float-tags
	docker images | grep nginx-with-dockerfy
	# pushing the entire repository will push all tagged images
	docker push socialcode/nginx-with-dockerfy

test: fmt lint is-open-source-clean nginx-with-dockerfy
	cd test && make test

test-and-log: fmt lint nginx-with-dockerfy
	cd test && make test-and-log

.PHONY: test
