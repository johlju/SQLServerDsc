# Suppressing this rule because ConvertTo-SecureString is used to simplify the tests.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
param ()

$configFile = [System.IO.Path]::ChangeExtension($MyInvocation.MyCommand.Path, 'json')
if (Test-Path -Path $configFile)
{
    <#
        Allows reading the configuration data from a JSON file,
        for real testing scenarios outside of the CI.
    #>
    $ConfigurationData = Get-Content -Path $configFile | ConvertFrom-Json
}
else
{
    $ConfigurationData = @{
        AllNodes = @(
            @{
                NodeName        = 'localhost'
                CertificateFile = $env:DscPublicCertificatePath

                UserName        = "$env:COMPUTERNAME\SqlAdmin"
                Password        = 'P@ssw0rd1'

                ServerName      = $env:COMPUTERNAME
                InstanceName    = 'DSCSQLTEST'

                # This is created by the SqlDatabase integration tests.
                DatabaseName    = 'Database1'

                # This is created by the SqlDatabaseUser integration tests.
                User1_Name      = 'User1'

                SchemaName      = 'dbo'
                TableName       = 'Table1'

                GetQuery        = @'
select b.name + '.' + a.name As ObjectName
from [$(DatabaseName)].sys.objects a
inner join [$(DatabaseName)].sys.schemas b
    on a.schema_id = b.schema_id
where a.name = '$(TableName)'
FOR JSON AUTO
'@

                TestQuery       = @'
if (select count(name) from [$(DatabaseName)].sys.objects where name = '$(TableName)') = 0
BEGIN
    RAISERROR ('Did not find table [$(TableName)] in database [$(DatabaseName)].', 16, 1)
END
ELSE
BEGIN
    PRINT 'Found table [$(TableName)] in database [$(DatabaseName)].'
END
'@

                SetQuery        = @'
CREATE TABLE [$(DatabaseName)].[dbo].[$(TableName)](
    [Name] [nchar](10) NULL
) ON [PRIMARY]
'@

            }
        )
    }
}

<#
    .SYNOPSIS
        Create a table in the database to use for the tests.
#>
Configuration DSC_SqlDatabaseObjectPermission_Prerequisites_Config
{
    Import-DscResource -ModuleName 'SqlServerDsc'

    node $AllNodes.NodeName
    {
        SqlScriptQuery 'CreateTable'
        {
            ServerName           = $Node.ServerName
            InstanceName         = $Node.InstanceName

            GetQuery             = $Node.GetQuery
            TestQuery            = $Node.TestQuery
            SetQuery             = $Node.SetQuery
            QueryTimeout         = 30
            Variable             = @(
                ('TableName={0}' -f $Node.TableName)
                ('DatabaseName={0}' -f $Node.DatabaseName)
            )

            PsDscRunAsCredential = New-Object `
                -TypeName System.Management.Automation.PSCredential `
                -ArgumentList @(
                    $Node.Username,
                    (ConvertTo-SecureString -String $Node.Password -AsPlainText -Force)
                )
        }
    }
}

<#
    .SYNOPSIS
        Grant a user single permission for a table in a database, also allows
        the user to grant the permission (GrantWithGrant).

    .NOTES
        This is a regression test for issue #1602. The next test should replace
        the permission GrantWithGrant with the permission Grant.
#>
Configuration DSC_SqlDatabaseObjectPermission_Single_GrantWithGrant_Config
{
    Import-DscResource -ModuleName 'SqlServerDsc'

    node $AllNodes.NodeName
    {
        SqlDatabaseObjectPermission 'Integration_Test'
        {
            ServerName           = $Node.ServerName
            InstanceName         = $Node.InstanceName
            DatabaseName         = $Node.DatabaseName
            SchemaName           = $Node.SchemaName
            ObjectName           = $Node.TableName
            ObjectType           = 'Table'
            Name                 = $Node.User1_Name
            Permission           = @(
                DSC_DatabaseObjectPermission
                {
                    State      = 'GrantWithGrant'
                    Permission = @('Select')
                }
            )

            PsDscRunAsCredential = New-Object `
                -TypeName System.Management.Automation.PSCredential `
                -ArgumentList @(
                    $Node.UserName,
                    (ConvertTo-SecureString -String $Node.Password -AsPlainText -Force)
                )
        }
    }
}

<#
    .SYNOPSIS
        Grant a user single permission for a table in a database.

    .NOTES
        This test is used for the previous regression test for issue #1602. This
        test should replace the previous test that set the permission GrantWithGrant
        with the permission Grant.
#>
Configuration DSC_SqlDatabaseObjectPermission_Single_Grant_Config
{
    Import-DscResource -ModuleName 'SqlServerDsc'

    node $AllNodes.NodeName
    {
        SqlDatabaseObjectPermission 'Integration_Test'
        {
            ServerName           = $Node.ServerName
            InstanceName         = $Node.InstanceName
            DatabaseName         = $Node.DatabaseName
            SchemaName           = $Node.SchemaName
            ObjectName           = $Node.TableName
            ObjectType           = 'Table'
            Name                 = $Node.User1_Name
            Permission           = @(
                DSC_DatabaseObjectPermission
                {
                    State      = 'Grant'
                    Permission = @('Select')
                }
            )

            PsDscRunAsCredential = New-Object `
                -TypeName System.Management.Automation.PSCredential `
                -ArgumentList @(
                    $Node.UserName,
                    (ConvertTo-SecureString -String $Node.Password -AsPlainText -Force)
                )
        }
    }
}

<#
    .SYNOPSIS
        Revoke a single permission for a user for a table in a database.
#>
Configuration DSC_SqlDatabaseObjectPermission_Single_Revoke_Config
{
    Import-DscResource -ModuleName 'SqlServerDsc'

    node $AllNodes.NodeName
    {
        SqlDatabaseObjectPermission 'Integration_Test'
        {
            ServerName           = $Node.ServerName
            InstanceName         = $Node.InstanceName
            DatabaseName         = $Node.DatabaseName
            SchemaName           = $Node.SchemaName
            ObjectName           = $Node.TableName
            ObjectType           = 'Table'
            Name                 = $Node.User1_Name
            Permission           = @(
                DSC_DatabaseObjectPermission
                {
                    State      = 'Grant'
                    Permission = @('Select')
                    Ensure     = 'Absent'
                }
            )

            PsDscRunAsCredential = New-Object `
                -TypeName System.Management.Automation.PSCredential `
                -ArgumentList @(
                    $Node.UserName,
                    (ConvertTo-SecureString -String $Node.Password -AsPlainText -Force)
                )
        }
    }
}
<#
    .SYNOPSIS
        Grant a user multiple permissions for a table in a database.
#>
Configuration DSC_SqlDatabaseObjectPermission_Multiple_Grant_Config
{
    Import-DscResource -ModuleName 'SqlServerDsc'

    node $AllNodes.NodeName
    {
        SqlDatabaseObjectPermission 'Integration_Test'
        {
            ServerName           = $Node.ServerName
            InstanceName         = $Node.InstanceName
            DatabaseName         = $Node.DatabaseName
            SchemaName           = $Node.SchemaName
            ObjectName           = $Node.TableName
            ObjectType           = 'Table'
            Name                 = $Node.User1_Name
            Permission           = @(
                DSC_DatabaseObjectPermission
                {
                    State      = 'Grant'
                    Permission = @('Select')
                }

                DSC_DatabaseObjectPermission
                {
                    State      = 'Deny'
                    Permission = @('Delete', 'Alter')
                }
            )

            PsDscRunAsCredential = New-Object `
                -TypeName System.Management.Automation.PSCredential `
                -ArgumentList @(
                    $Node.UserName,
                    (ConvertTo-SecureString -String $Node.Password -AsPlainText -Force)
                )
        }
    }
}

<#
    .SYNOPSIS
        Revoke multiple permissions for a user for a table in a database.
#>
Configuration DSC_SqlDatabaseObjectPermission_Multiple_Revoke_Config
{
    Import-DscResource -ModuleName 'SqlServerDsc'

    node $AllNodes.NodeName
    {
        SqlDatabaseObjectPermission 'Integration_Test'
        {
            ServerName           = $Node.ServerName
            InstanceName         = $Node.InstanceName
            DatabaseName         = $Node.DatabaseName
            SchemaName           = $Node.SchemaName
            ObjectName           = $Node.TableName
            ObjectType           = 'Table'
            Name                 = $Node.User1_Name
            Permission           = @(
                DSC_DatabaseObjectPermission
                {
                    State      = 'Grant'
                    Permission = @('Select')
                    # Intentionally leaving this permission on the node.
                    Ensure     = 'Present'
                }

                DSC_DatabaseObjectPermission
                {
                    State      = 'Deny'
                    Permission = @('Delete', 'Alter')
                    Ensure     = 'Absent'
                }
            )

            PsDscRunAsCredential = New-Object `
                -TypeName System.Management.Automation.PSCredential `
                -ArgumentList @(
                    $Node.UserName,
                    (ConvertTo-SecureString -String $Node.Password -AsPlainText -Force)
                )
        }
    }
}
