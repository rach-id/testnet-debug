#!/bin/bash

# This script starts a Celestia-app, creates a validator with the provided parameters, then
# keeps running it validating blocks.

# check if environment variables are set
check_env() {
  if [[ -z "${MONIKER}" || -z "${AMOUNT}" ]]
  then
    echo "Environment not setup correctly. Please set: MONIKER, AMOUNT variables"
    exit 1
  fi
}

# install needed dependencies
install_dependencies() {
  apk add curl iproute2
}

# introduce latency
add_latency_if_specified() {
  if [[ -n  "${LATENCY}" ]]
  then
    tc qdisc add dev eth0 root netem delay ${LATENCY}
  fi
}

create_validator() {
  # wait for the node to get up and running
  while true
  do
    status_code=$(curl --write-out '%{http_code}' --silent --output /dev/null localhost:26657/status)
    if [[ "${status_code}" -eq 200 ]] ; then
      break
    fi
    echo "Waiting for node to be up..."
    sleep 5s
  done

  # create validator
  celestia-appd tx staking create-validator \
    --amount="${AMOUNT}" \
    --pubkey="$(celestia-appd tendermint show-validator)" \
    --moniker="${MONIKER}" \
    --chain-id="test" \
    --commission-rate=0.1 \
    --commission-max-rate=0.2 \
    --commission-max-change-rate=0.01 \
    --min-self-delegation=1000000 \
    --from="${MONIKER}" \
    --keyring-backend=test \
    --broadcast-mode=block \
    --yes
}

init_chain() {
  celestia-appd init "test" 2> /dev/null
  # needed to have correct structure
  celestia-appd keys add corex --keyring-backend="test" 2> /dev/null
  celestia-appd add-genesis-account $(celestia-appd keys show corex -a --keyring-backend="test") 50000000000utia > /dev/null
  celestia-appd gentx corex 5000000000utia --keyring-backend="test" --chain-id "test" > /dev/null
  celestia-appd collect-gentxs > /dev/null
}

copy_necessary_chain_files() {
  cp /opt/keyring-test/* ~/.celestia-app/keyring-test/
  cp /opt/config/genesis.json ~/.celestia-app/config/genesis.json
  cp /opt/config/config.toml ~/.celestia-app/config/config.toml
}

update_timeouts() {
    if [[ -n  "${TIMEOUT_COMMIT}" ]]
    then
      sed -i "s/timeout-commit = \"6s\"/timeout-commit = \""${TIMEOUT_COMMIT}"\"/g" ~/.celestia-app/config/config.toml
    fi
    if [[ -n  "${TIMEOUT_PROPOSE}" ]]
    then
      sed -i "s/timeout-commit = \"6s\"/timeout-commit = \""${TIMEOUT_PROPOSE}"\"/g" ~/.celestia-app/config/config.toml
    fi
}

# start node
start_node() {
  celestia-appd start \
  --moniker="${MONIKER}" \
  --p2p.persistent-peers=81c92b8dde62536849897be8535a8b2822d02040@core0:26656 \
  --rpc.laddr=tcp://0.0.0.0:26657
}

main() {
  check_env
  init_chain
  copy_necessary_chain_files
  install_dependencies
  add_latency_if_specified
  update_timeouts
  create_validator &
  start_node
}

main