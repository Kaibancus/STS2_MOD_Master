#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dll=Join-Path (Split-Path -Parent $repo) 'game\data_sts2_windows_x86_64\sts2.dll'
if ((Get-FileHash -LiteralPath $dll).Hash -cne '0861BFA1DF347538D932F22D580E75420F08082792EB914E53B4882764ACDBE9') { throw 'Unexpected assembly.' }
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
namespace CatalogRelations {
 public static class Reader {
  static string TypeName(MetadataReader md, EntityHandle h) {
   if(h.Kind==HandleKind.TypeDefinition) { var t=md.GetTypeDefinition((TypeDefinitionHandle)h);
    return t.IsNested ? TypeName(md,t.GetDeclaringType())+"+"+md.GetString(t.Name) : md.GetString(t.Namespace)+"."+md.GetString(t.Name); }
   if(h.Kind==HandleKind.TypeReference) { var t=md.GetTypeReference((TypeReferenceHandle)h); return md.GetString(t.Namespace)+"."+md.GetString(t.Name); }
   return h.Kind.ToString();
  }
  static string MethodName(MetadataReader md, EntityHandle h) {
   if(h.Kind==HandleKind.MethodDefinition) {var m=md.GetMethodDefinition((MethodDefinitionHandle)h);return TypeName(md,m.GetDeclaringType())+"::"+md.GetString(m.Name);}
   if(h.Kind==HandleKind.MemberReference) {var m=md.GetMemberReference((MemberReferenceHandle)h);return TypeName(md,m.Parent)+"::"+md.GetString(m.Name);}
   return h.Kind.ToString();
  }
  public static List<Dictionary<string,string>> Read(string path) {
   var ops=typeof(OpCodes).GetFields(BindingFlags.Public|BindingFlags.Static).Where(f=>f.FieldType==typeof(OpCode))
    .Select(f=>(OpCode)f.GetValue(null)).ToDictionary(o=>unchecked((ushort)o.Value));
   var result=new List<Dictionary<string,string>>();
   using var file=File.OpenRead(path); using var pe=new PEReader(file);var md=pe.GetMetadataReader();
   foreach(var th in md.TypeDefinitions) {
    var type=md.GetTypeDefinition(th); string source=TypeName(md,th), outer=source.Split('+')[0];
    if(!outer.StartsWith("MegaCrit.Sts2.Core.Models.")) continue;
    foreach(var mh in type.GetMethods()) {
     var m=md.GetMethodDefinition(mh); if(m.RelativeVirtualAddress==0)continue;
     byte[] bytes=pe.GetMethodBody(m.RelativeVirtualAddress).GetILBytes();
     for(int i=0;i<bytes.Length;) {
      ushort code=bytes[i++]; if(code==0xfe)code=(ushort)(0xfe00|bytes[i++]); var op=ops[code]; int size=0;
      switch(op.OperandType) {
       case OperandType.InlineNone:break;
       case OperandType.ShortInlineBrTarget:case OperandType.ShortInlineI:case OperandType.ShortInlineVar:size=1;break;
       case OperandType.InlineVar:size=2;break;
       case OperandType.InlineI8:case OperandType.InlineR:size=8;break;
       case OperandType.InlineSwitch:size=4+BitConverter.ToInt32(bytes,i)*4;break;
       default:size=4;break;
      }
      if(op.OperandType==OperandType.InlineMethod) {
       var h=MetadataTokens.EntityHandle(BitConverter.ToInt32(bytes,i));
       string target=null, kind=null;
       if(h.Kind==HandleKind.MethodSpecification) {
        var spec=md.GetMethodSpecification((MethodSpecificationHandle)h);var name=MethodName(md,spec.Method);
        var blob=md.GetBlobReader(spec.Signature);blob.ReadByte();int n=blob.ReadCompressedInteger();
        if(n==1&&blob.ReadSignatureTypeCode()==SignatureTypeCode.TypeHandle) {
         string argument=TypeName(md,blob.ReadTypeHandle());
         if(argument.StartsWith("MegaCrit.Sts2.Core.Models.Cards.") ||
            argument.StartsWith("MegaCrit.Sts2.Core.Models.Relics.") ||
            argument.StartsWith("MegaCrit.Sts2.Core.Models.Characters.")) {
          target=argument;kind="modelReference";
         }
        }
       } else {
        var name=MethodName(md,h);
        if(name.Contains("CardEnergyCost::") && !name.Contains("get_")) {target=name;kind="energyOperation";}
        if(name.StartsWith("MegaCrit.Sts2.Core.Models.CardModel::") && name.Contains("StarCost")) {target=name;kind="starOperation";}
       }
       if(target!=null) result.Add(new Dictionary<string,string>{{"source",outer},{"method",md.GetString(m.Name)},
        {"declaring",source},{"target",target},{"kind",kind},{"token",$"0x{MetadataTokens.GetToken(mh):X8}"}});
      }
      if(op.OperandType==OperandType.InlineType) {
       string target=TypeName(md,MetadataTokens.EntityHandle(BitConverter.ToInt32(bytes,i)));
       if(target.StartsWith("MegaCrit.Sts2.Core.Models.Characters."))
        result.Add(new Dictionary<string,string>{{"source",outer},{"method",md.GetString(m.Name)},
         {"declaring",source},{"target",target},{"kind","characterTypeCheck"},{"token",$"0x{MetadataTokens.GetToken(mh):X8}"}});
      }
      i+=size;
     }
    }
   }
   return result;
  }
 }
}
'@
$rows=[CatalogRelations.Reader]::Read($dll)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), ($rows | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
$rows | Group-Object kind | Select-Object Name,Count
