# Rewards Distributor

A singleton rewards distributor replacing the Universal Rewards Distributor (URD) for new campaigns. Each campaign has an isolated balance and timelocked Merkle roots that anyone can accept once the timelock has elapsed. The updater submits roots and transfers its own role, while the sentinel transfers its own role; both can revoke pending roots and pause claims. Claims keep the URD's double-hashed, sorted-pair Merkle format but omit the token from the leaf.
