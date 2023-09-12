## Data Formatting

For interoperability, all cmdlets in this project should return either a `[PSCustomObject]` or a collection of `[PSCustomObject]` as appropriate. This will allow them to be serialized and deserialized consistently.
```pwsh
function Get-Foo {
    ...

    return $foos | $ {[PSCustomObject]@{
        Bar = $_.bar
        Baz = $_.baz
    }}
}
```

### Custom Classes

To make writing code easier, cmdlets may define their output types as classes.
```pwsh
class Device {
    [string]$Brand
    [string]$Model
    [string]$VendorSku
}

class Rack {
    [string]$Brand
    [string]$Model
    [Device[]]$Devices = [Device[]]::new(8)
}

function Get-Racks {
    ...

    return $racks | % {[Rack]@{
        Brand = $_.brand
        Model = $_.model
        Devices = $_.devices
    }}
}
```
See [about_Classes](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_classes?view=powershell-7.3) for more information.

Note: When casting deserialized data from a `PSCustomObject` to a class, the cast will fail if the class contains nested collections of classes. (e.g. if `Device` contained a collection of a specific class type, a `PSCustomObject` would not be able to be casted to a `Rack`)

## Serialization
Migration data can be stored using `Set-MigrationData` and later retrieved using `Get-MigrationData`. `Get-MigrationData` will return `[PSCustomObject]`s for any data that was previously stored.
