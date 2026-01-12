.PHONY: docker-deploy

contract:
	cd contracts/settlement && stellar contract build --profile release-with-logs --optimize

contract-deploy: contract
	stellar contract deploy \
		--wasm target/wasm32v1-none/release-with-logs/settlement.wasm \
		--source test \
		--network testnet \
		-- --admin $$(stellar keys address test) \
		--token_a $$(stellar contract id asset --asset native --network testnet) \
		--token_b $$(stellar contract id asset --asset native --network testnet)

docker-deploy:
	docker-compose build
	docker tag stellar-darkpool-matching-engine:latest ymcrcat/stellar-darkpool-matching-engine:latest
	docker push ymcrcat/stellar-darkpool-matching-engine:latest

cvm-deploy:
	npx phala deploy --interactive