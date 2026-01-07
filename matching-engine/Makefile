.PHONY: deploy

deploy:
	docker-compose build
	docker tag stellar-darkpool-matching-engine:latest ymcrcat/stellar-darkpool-matching-engine:latest
	docker push ymcrcat/stellar-darkpool-matching-engine:latest
