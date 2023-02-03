# vSphere Discovery/Inventory

Generate multiple reports with a single script of a vSphere environment to be used for discovery/inventory.

This repo has a layout that is meant to support being downloaded as a .ZIP file, extracted and then contain everything necessary to execute; the `vsphere-inventory` folder can be extracted and placed on the target system.

Each report that is generated from this script is meant to be self containing, in that each report contains enough context that it can be read/shared without requiring information from any other report.

Some of the reports do contain redundant information, again, context is everything and each report needs to stand on it's on merit.

There are a total of 10 reports that are generated; a list of them is below with a brief explination of each.

| Report Name | Description |
|:------------|:------------|
| Cluster Summary Report | General summary of vSphere cluster information, total host and VM counts, EVC, HA, etc.
| vCenter Component Report | This report is becoming obsolete but it was meant to identify the presense of an external server hosting PSC/SSO roles.
| vCenter License Report | This report will provide all installed and in-use licenses according to vCenter. There is currently an issue with how this information is queried for vCenters that operate in linked mode, in that, you will get duplicate licenses in your report, so, be aware you may need to filter until it gets 'enhanced'
| vCenter Summary Report | Summary counts of vSphere datacenters, clusters, hosts & VMs. This is good if you want to create a trend report based on a snapshot in time when this report is run, etc.
| VM Inventory Report | This is an inventory of virtual machines with relevent information about each VM, guest OS, hardware versions, IP addresses, annotations, status, and a lot more.
| VM Mapping Report | This report containes similar information to the inventory report but it focused on providing geographical detail on where a VM is located in the environment.
| VM Network Adapter Report | Contains information about VM virtual network adapters, IP address(s), MAC address(s), adapter type/driver, etc.
| VMHost Mapping Report | Containes geographical information about the ESXi host and where it is located in the environment; vCenter, datacenter, cluster, etc.
| VMHost Network Configuration Report | This report does a lot of hard work behind the scenes and could be considered the star of this show; it provides a lot of detail that you would otherwise need to pull from numerous places. It was written with the intent to pull accurate, critical network configuration data from an ESXi host including physical adapter configuration and virtual (vmkernel) configurration, regardless if vSphere Standard Switches or Distributed Switches are in-use. It also does not desriminate which TCP/IP stack a vmk interface is assigned to, however it will report if those interfaces are tagged for a particular traffic type (Management, vMotion, FT, vSphere Replication, etc.). It can be used to quickly hunt out network inconsistencies that would interefere with other cluster functions such as MTU size, default gateways, etc.
| VMHost Services Report | This report pulls detail on critical services such as NTP and Syslog and gives detail on status and configuration(s).

## Getting Started

See [INSTRUCTIONS](/vSphere-Inventory/INSTRUCTIONS.md)
