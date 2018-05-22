# Instructions

1. **Extract** the folder to a desired location; we will use `$HOME\Desktop` for examples.
2. **Launch**/Load PowerCLI.
> Depending on what version of PowerCLI you have installed, you may have the option to open the PowerCLI console, or you might just prefer to manually load the Module. If you have questions about this please contact the person(s) listed at the bottom of the instructions.
3. **Navigate** / `cd` to where the `vSphere-Inventory` folder resides to make execution a bit easier. `cd $HOME\Desktop\vSphere-Inventory`
4. **Connect** to all desired vCenter Servers with appropriate credentials (this script only reads various inventory details).
    ```powershell
    # Connect to vCenter 'vc1.corp.com'
    C:\Users\Administrator\Desktop\vSphere-Inventory>Connect-VIServer -Server vc1.corp.com -Credential (Get-Credential)

    # Connect to vCenter 'vc2.corp.com'
    C:\Users\Administrator\Desktop\vSphere-Inventory>Connect-VIServer -Server vc2.corp.com -Credential (Get-Credential)
    ```

5. **Run** the inventory script
    ```powershell
    C:\Users\Administrator\Desktop\vSphere-Inventory>.\Invoke-Inventory.ps1
    ```

    Alternatively, you can also run the script with the `-Verbose` switch, which will provide a more verbose execution output. That being said, it becomes difficult to diagnose errors when running with `-Verbose`.

6. **Verify** Reports: The script should generate a unique folder using a timestamp for the folder name, which will contain numerous `.csv` report files.
> If you encountered any errors, please let the person(s) below know, if can't seem to figure out what is causing the errors.
7. **Compress** Report: Please compress each of the report directories and return them to the person requesting this inventory.

# About
If you have any questions, contact the people, below.

| Name | Email
|:-----|:------
| Kevin Kirkpatrick |
