.PHONY: docker-deploy

docker-deploy:
	docker-compose build
	docker tag stellar-darkpool-matching-engine:latest ymcrcat/stellar-darkpool-matching-engine:latest
	docker push ymcrcat/stellar-darkpool-matching-engine:latest

cvm-deploy:
	npx phala deploy --interactive