#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$assembly=Join-Path (Split-Path -Parent $repo) 'game\data_sts2_windows_x86_64\sts2.dll'
if ((Get-FileHash -LiteralPath $assembly).Hash -cne '0861BFA1DF347538D932F22D580E75420F08082792EB914E53B4882764ACDBE9') { throw 'Unexpected assembly version.' }
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
namespace CatalogStatic {
    public sealed class Row {
        public string Model { get; set; }
        public string Namespace { get; set; }
        public string BaseType { get; set; }
        public string Token { get; set; }
        public bool Abstract { get; set; }
        public bool PublicDefaultConstructor { get; set; }
    }
    public static class Inventory {
        public static List<Row> Read(string path) {
            using var file = File.OpenRead(path);
            using var pe = new PEReader(file);
            var md = pe.GetMetadataReader();
            var rows = new List<Row>();
            foreach (var handle in md.TypeDefinitions) {
                var type = md.GetTypeDefinition(handle);
                string ns = md.GetString(type.Namespace);
                if (type.IsNested || !(ns == "MegaCrit.Sts2.Core.Models.Cards" ||
                    ns == "MegaCrit.Sts2.Core.Models.Cards.Mocks" ||
                    ns == "MegaCrit.Sts2.Core.Models.Relics" || ns == "MegaCrit.Sts2.Core.Models.Characters" ||
                    ns == "MegaCrit.Sts2.Core.Models.CardPools" || ns == "MegaCrit.Sts2.Core.Models.RelicPools")) continue;
                string baseName = "";
                if (type.BaseType.Kind == HandleKind.TypeDefinition) {
                    var b = md.GetTypeDefinition((TypeDefinitionHandle)type.BaseType);
                    baseName = md.GetString(b.Namespace) + "." + md.GetString(b.Name);
                } else if(type.BaseType.Kind == HandleKind.TypeReference) {
                    var b = md.GetTypeReference((TypeReferenceHandle)type.BaseType);
                    baseName = md.GetString(b.Namespace) + "." + md.GetString(b.Name);
                }
                bool ctor = false;
                foreach(var m in type.GetMethods()) {
                    var method = md.GetMethodDefinition(m);
                    if(md.GetString(method.Name) == ".ctor" &&
                        (method.Attributes & MethodAttributes.MemberAccessMask) == MethodAttributes.Public) {
                        var sig=md.GetBlobReader(method.Signature);
                        sig.ReadSignatureHeader();
                        if(sig.ReadCompressedInteger()==0) ctor=true;
                    }
                }
                rows.Add(new Row { Model=md.GetString(type.Name), Namespace=ns, BaseType=baseName,
                    Token=$"0x{MetadataTokens.GetToken(handle):X8}",
                    Abstract=(type.Attributes & TypeAttributes.Abstract)!=0, PublicDefaultConstructor=ctor });
            }
            return rows;
        }
    }
}
'@
$rows=[CatalogStatic.Inventory]::Read($assembly)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), ($rows | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
$rows | Group-Object Namespace | Select-Object Name,Count
$rows | Where-Object { -not $_.Abstract -and -not $_.PublicDefaultConstructor } | Select-Object Model,BaseType,PublicDefaultConstructor
