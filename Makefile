include .env

deploy-Avalanche:
	@forge script script/DeployAll.s.sol:DeployAll \
	--rpc-url $(AVAX_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify \
	--etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
	
deploy-Fuji:
	@forge script script/DeployAll.s.sol:DeployAll \
	--rpc-url $(AVAXFUJI_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast \
	--verify \
  	--verifier-url https://api.avascan.info/v2/network/testnet/evm/43113/ \
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