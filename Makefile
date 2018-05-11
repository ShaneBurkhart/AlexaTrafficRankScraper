.PHONY: run

NAME=blog_traffic_scraper
BASE_TAG=shaneburkhart/${NAME}

all: run

run: build
	docker run --rm --name ${NAME} --env-file user.env -v $(shell pwd):/app ${BASE_TAG}

build:
	 docker build -t ${BASE_TAG} .

stop:
	docker stop ${NAME} || echo "Nothing to stop..."

clean: stop
	docker rm ${NAME} || echo "Nothing to remove..."

ps:
	docker ps
