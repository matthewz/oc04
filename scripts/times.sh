resources=(
  null_resource.k8s_master:
  null_resource.k8s_master_init
  null_resource.k8s_worker1
  null_resource.k8s_worker2
  null_resource.setup_common_master
  null_resource.setup_common_worker1
  null_resource.setup_common_worker2
)
for resource in "${resources[@]}"; do
  grep elapsed k8s-rebuild_out.txt | grep "${resource}" | tail -1 
done
