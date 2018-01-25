<#

This is a very rough version of this script and I plan to clean it up more later on.

Steps to get the VM environment set up:

1. Install the Hyper-V Windows feature (Other hypervisors like Vmware and Virtualbox will no longer work)
2. Create a Windows 10 VM in Hyper-V, install Windows 10 (Either Education, Enterprise, or Pro), and once Cortana starts talking (plzhalp) press Shift + Ctrl + F3. It will reboot to Audit mode.
3. Once it gets to the desktop (A sysprep window should be open when you get to the desktop), create a snapshot called "Base Start".
4. On line 111 of this script, make sure the -Path argument for Get-ChildItem is the same directory as where the VM is.
    - Sometimes the default folder is "C:\Users\Public\Documents\Hyper-V\Virtual Hard Disks\" or "C:\Users\<YOUR USERNAME>\Documents\Hyper-V\Virtual Hard Disks\"
    - Make note of where it is during the VM creation process and change it on that line.

From there, you have your initial build. Every time you run this script, it will delete the "Final" snapshot it makes and start back at "Base Start".

To create the ISOCreation environment:

1. Create a folder in the root of C: called "ISOCreation".
2. Create three folders inside of that one: ISO, Split, and Win10.
3. Extract the contents of the Windows 10 ISO you have downloaded into the Win10 folder. (Protip: In the root of the Win10 folder, it should have setup.exe)
4. In the extracted folder, navigate to sources and delete install.wim (C:\ISOCreation\install.wim). We don't need this. If it's not install.wim, it might be install.esd. Delete it.

Other things needed:
1. Windows 10 1709 ADK (https://developer.microsoft.com/en-us/windows/hardware/windows-assessment-deployment-kit) 
    - You only need the deployment tools from it, none of the assessment stuff when you go to install it.
    - I can't remember which one it is to install from ADK, but look for "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe" and if it's there you are good.
2. PSWindowsUpdate (https://www.powershellgallery.com/packages/PSWindowsUpdate/2.0.0.3) -  Applies Windows Updates to the image through Powershell. It's magic.
    - Use "Save-Module -Name PSWindowsUpdate -Path <Path>" to save it to your local machine.
    - You need the folder PSWindowsUpdate folder to be copied in whole, not the folder you saved the module to.
3. Make a folder somewhere with all the software and the PSWindowsUpdate folder you downloaded so you can easily have the script copy it to the VM.

This should be everything needed to get it going. I've put comments in places in the script to explain what does what and what you need to add yourself.

I'm hoping to expand this script out and make it not so freaking ugly at some point, but right now this is a very rough version and it works great for me. I just need to make it look and run cleaner.

#>

$creds = New-Object System.Management.Automation.PSCredential("Administrator",(New-Object System.Security.SecureString)) #Defines the local administrator account (Which has a blank password)
$vmName = "Win10" #Replace this with whatever the VM's name is in Hyper-V

$deleteFiles = (Get-ChildItem -Path "C:\ISOCreation\install.wim"),(Get-ChildItem -Path "C:\ISOCreation\Split\"),(Get-ChildItem -Path "C:\ISOCreation\Win10\sources\" | Where-Object -Property "Name" -Like "*.swm") 

foreach ($file in $deleteFiles) #Cleans up any previous files that were made in the last run of the script.
{
    Remove-Item -Path $file.FullName -Force
}

Get-VMSnapshot -VMName "Win10" | Where-Object -Property "Name" -eq "Final" | Remove-VMSnapshot #Removes the "Final" snapshot from a previous run

Get-VMSnapshot -VMName "Win10" | Where-Object -Property "Name" -eq "Base Start" | Restore-VMSnapshot -Confirm:$false #Reverts back to the base snapshot.

Start-VM -Name $vmName

Start-Sleep -Seconds 120

#Starting the VM is a little tricky to judge, so I set a 120 second timer on the script to give it enough time to start up.

$vmSession = New-PSSession -VMName "Win10" -Credential $creds #Creates a PSSession to the VM

#This command below is just a basis for what you need, but just change the -Path variable to point to wherever you have your install files and PSWindowsUpdate folder at.
Copy-Item -ToSession $vmSession -Path "Path/to/your/files/folder/" -Destination "C:\Users\Administrator\Desktop\Installables" -Recurse

$vmHostName = Invoke-Command -VMName $vmName -Credential $creds -ScriptBlock { $env:COMPUTERNAME } #I can't remember what exactly I used this for, which it's probably not used at all.

Invoke-Command -VMName $vmName -Credential $creds -ScriptBlock { cd "C:\Users\Administrator\Desktop\Installables" ; Set-ExecutionPolicy -ExecutionPolicy Bypass } #Setting our location to the Installables folder and setting the ExecutionPolicy to Bypass for any unsigned PSScripts. When the ISO is made, any changes we made to the ExecutionPolicy is reversed.
Start-Process -ArgumentList
<#

This part right here is up to you on how you approach this, because it's the things you want to install or do. If you have an MSI file you can install, you'd do something like this:
Invoke-Command -VMName $vmName -Credential $creds -ScriptBlock { Start-Process -Path "msiexec" -ArgumentList "/i '.\ImportantSoftware\install.msi' /qn /norestart" -wait

Anything along the lines of that. If it's like a propriatary installer, then it would go something like this (Depending on the command line args):
Invoke-Command -VMName $vmName -Credential $creds -ScriptBlock { Start-Process -Path ".\NonMSIsoftware\Adobe_ReadRAR_X.exe" -ArgumentList "/s" -wait

I'd highly advise using MSI files for installs if you can, because they are the cleanest and easiest way to install things. Adobe Flash, Adobe Reader, Chrome, and Java distribute MSI files in some form. Firefox is their own installer, but it's easy to work around.

If anything, you could add in a pause in the script and install things by hand until you have it proceed. You could add this code:
Write-Output "Press any key to continue..."
$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Put any commands you want done in between the Begin/End Custom Install Options comments.

#>

#Begin Custom Install Options

Invoke-Command -VMName $vmName -Credential $creds -ScriptBlock { Put Commands Here } #Copy this as many times you need to.

#End Custom Install Options

Invoke-Command -VMName $vmName -Credential $creds -ScriptBlock { cd ".\PSWindowsUpdate\" ; Import-Module PSWindowsUpdate ; Get-WUInstall -AcceptAll Software -Verbose -IgnoreReboot } #Installs Windows Updates

Invoke-Command -VMName $vmName -Credential $creds -ScriptBlock { New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Sysprep" -PropertyType "ExpandString" -Value "cmd.exe /C taskkill /IM sysprep.exe && timeout /t 5 && ""C:\Windows\system32\sysprep\sysprep.exe"" /generalize /oobe /shutdown" } #We create a registry key to initiate sysprep after rebooting.

Invoke-Command -VMName $vmName -Credential $creds -ScriptBlock { Restart-Computer -Force } #Restarts the VM and in this process it 

Start-Sleep -Seconds 90

#Now the script sleeps for 1.5 minutes to wait for it to finish the reboot and whatnot.

while ((Get-VM -Name $vmName).State -eq "Running") #Now we're just waiting for the VM to completely shutdown.
{
    Write-Output "Waiting..."
    Start-Sleep -Seconds 5
}

Write-Output "Done!" #Done... With this part.

Checkpoint-VM -Name $vmName -SnapshotName "Final" #Now it creates the Final snapshot we need before we mount the VM's VHD.

$imageLocation = Get-ChildItem -Path "C:\HyperV\Win10\Virtual Hard Disks\" | Sort-Object -Property "LastWriteTime" -Descending | Select-Object -First 1 #Refer to step 4 of the VM environment setup instructions at the top of this script.

$mountImage = Mount-DiskImage -ImagePath $imageLocation.FullName -Access ReadOnly -StorageType VHDX -PassThru #Mounts the snapshot we made as a hard drive.

$driveLetter = (Get-Disk | Where-Object -Property "Location" -eq $imageLocation.FullName | Get-Partition | Sort-Object -Property "Size" -Descending | Select-Object -First 1).DriveLetter

$driveLetter += ":\" #Grabbed the drive letter of the mounted VHD.

New-WindowsImage -CapturePath $driveLetter -ImagePath "C:\ISOCreation\install.wim" -CompressionType Maximum -Name "Win10_1709" -CheckIntegrity -Setbootable -Verify -Verbose #Now we create a WIM file from that mounted VHD.

Split-WindowsImage -ImagePath "C:\ISOCreation\install.wim" -SplitImagePath "C:\ISOCreation\Split\install.swm" -FileSize "3500" -CheckIntegrity -Verbose #Now we split the WIM file into multiple files. This comes in handy when you make flash drives that are FAT32 formatted since that's what a UEFI bootable Windows Installer requires.

$swmFiles = Get-ChildItem -Path "C:\ISOCreation\Split\"

foreach ($file in $swmFiles) #Copying all of the SWM files to the extracted ISO folder we made.
{
    Copy-Item -Path $file.FullName -Destination "C:\ISOCreation\Win10\sources\"
}

$curdate = Get-Date -Format MM_dd_yyyy
Start-Process -FilePath "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe" -ArgumentList "-m -o -u2 -udfver102 -bootdata:2#p0,e,bc:\ISOCreation\Win10\boot\etfsboot.com#pEF,e,bc:\ISOCreation\Win10\efi\microsoft\boot\efisys.bin c:\ISOCreation\Win10 c:\ISOCreation\ISO\Win10_1709_$curDate.iso" -Wait #Now we make a bootable ISO.

Dismount-DiskImage -ImagePath $imageLocation.FullName #Unmounts the VHD.

#Now we're done.