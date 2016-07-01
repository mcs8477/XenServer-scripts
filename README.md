# XenServer-scripts
PowerShell scripts for XenServer

This repository contains various little PowerShell scripts that contain some pretty hard to find commands
for XenServer and XenDesktop.  XenDesktop commands are slightly easier to find via the PowerShell tab in
the XenDesktop console as it basically records everything you do in the PowerShell Equivolent (You just 
need to sift through it all).  XenServer PowerShell commands aren't even known by Citrix Tech Support or Citrix
Sales Engineers. The best answers I got were the Shell Script commands, then try to figure out the subtle 
differences in the PowerShell commandlets.


Increase-Xenhdd.ps1

Overview: 
  Prompts for a XenServer Pool Master(s) and a minimum hard drive size then spins through all the VMs
  in the pool to find any that don't meet the requirement.  If the hard drive should be increased,
  it then checks XenDesktop to determine if there is an active user session. If not, the script will 
  then shutdown the VM, and issue the XenServer command to increase the size of the VM's hard drive,
  power it back on and then issue the remote Windows command to extend the drive.  It will create a report
  (.CSV file) at the end of the script of all the VMs that have a hard drive under the minimum specified.
  
Assumptions:
  * Tested for Windows 7 VMs running on XenServer 6.2 with XenDesktop 5.6
  * Tested with VMs that contain a single hard drive (c:\)
  * XenServers and VMs are part of the same domain, and the user credentials provide necessary rights to perform actions
  * Must be run from a XenDesktop controller to be able to use the XenDesktop PowerShell Commandlets, Citrix has not 
    provided a method of installing them on a separate computer for managment.
