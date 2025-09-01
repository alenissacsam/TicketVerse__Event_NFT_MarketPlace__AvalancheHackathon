include .env

install:
	@forge install cyfrin/foundry-devops
	@forge install smartcontractkit/chainlink-brownie-contracts
	@forge install openzeppelin/openzeppelin-contracts

deploy-Avalanche:
	@forge script script/DeployAll.s.sol:DeployAll \
	--rpc-url $(AVAX_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify \
	--etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
	
deploy-Fuji:
	@forge script script/DeployAll.s.sol:DeployAll \
	--rpc-url $(AVAXFUJI_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast \
	-vvvv

deploy-Local:
	@forge script script/DeployAll.s.sol:DeployAll \
	--rpc-url $(ANVIL_RPC_URL) --private-key $(ANVIL_PRIVATE_KEY) \
	--broadcast -vvvv

deploy-sepolia:
	@forge script script/DeployAll.s.sol:DeployAll \
	--rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) \
	--broadcast --verify --verifier blockscout \
  	--verifier-url 'https://eth-sepolia.blockscout.com/api/'