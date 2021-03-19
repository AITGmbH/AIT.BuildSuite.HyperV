# Hyper-V Server task

Remote control a virtual machine on a (remote) Hyper-V Server. The Azure Pipelines task supports start and stop a virtual machine plus create, restore and delete Hyper-V snapshots (without SCVMM). 

### Requirements
-------
* Build Agent must have Hyper-V PowerShell cmdlets installed (no SCVMM needed)
* Hyper-V PowerShell cmdlets must be compatible with your Hyper-V server (please check Microsoft Hyper-V documention)
* Documentation: [Remotely manage Hyper-V -> Availability and compatibility](https://technet.microsoft.com/en-us/library/dn632582.aspx)
and [Hyper-V Module](https://technet.microsoft.com/itpro/powershell/windows/hyper-v/index)
* Build Agent service user must be member of "Hyper-V Administrators" group on (remote) Hyper-V server

### Configuration
-------
* Add VM name(s) and the host name to start or stop a VM
* Additionally a snapshot name required to create, restore or delete snapshots

### Changelog ###
-------
* Changes since 5.1.65: Replaced DISM based HyperV PowerShell cmdlet check; refactored code, removed preview state  
* Changes since 5.1.70: Added author to task.json
* Changes since 6.0.0: Added support for multiple VMs names in one build step, added support for deleting snapshots, code refactoring and cleanup
* Changes since 6.0.8: Added information about data protection
* Changes since 6.1.0: Adapted Azure DevOps rebranding in certain files/places, opensourced version on GitHub
* Changes since 7.0.0: Moved from Powershell to Powershell3 execution handler, added direct turn off of VMs, renamed action StopVM to ShutdownVM, fixed bug in vmeventing (missing parameter), refactored code based on PSScriptAnalyzer
* Changes since 7.0.36: Removed non-existent parameter for hyperv cmdlet version 1.0 (only affects old hyper-v versions)

### Known limitions
-------

# Additional Links
-------
* [AIT-Homepage](http://www.aitgmbh.de/)
* [AIT TFS-Tools](http://www.aitgmbh.de/downloads/team-foundation-server-tools.html)

# Privacy information
-------
This extension operates completely locally and does not process any personal data on external computers. 
For general information on data protection, please refer to our data protection declaration.