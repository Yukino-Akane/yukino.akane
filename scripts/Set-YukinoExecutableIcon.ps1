param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath,

    [Parameter(Mandatory = $true)]
    [string]$IconPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $ExePath)) {
    throw "Executable not found: $ExePath"
}
if (-not (Test-Path -LiteralPath $IconPath)) {
    throw "Icon file not found: $IconPath"
}

$typeName = "YukinoExecutableIconResourceUpdater"
if (-not ($typeName -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;

public static class YukinoExecutableIconResourceUpdater
{
    private const ushort RT_ICON = 3;
    private const ushort RT_GROUP_ICON = 14;
    private const uint LOAD_LIBRARY_AS_DATAFILE = 0x00000002;
    private const uint LOAD_LIBRARY_AS_IMAGE_RESOURCE = 0x00000020;
    private const int ERROR_RESOURCE_TYPE_NOT_FOUND = 1813;

    private delegate bool EnumResourceNamesProc(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, IntPtr lParam);
    private delegate bool EnumResourceLanguagesProc(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, ushort wLanguage, IntPtr lParam);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadLibraryEx(string lpFileName, IntPtr hFile, uint dwFlags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeLibrary(IntPtr hModule);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr BeginUpdateResource(string pFileName, bool bDeleteExistingResources);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool EndUpdateResource(IntPtr hUpdate, bool fDiscard);

    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "UpdateResourceW")]
    private static extern bool UpdateResourceInt(IntPtr hUpdate, IntPtr lpType, IntPtr lpName, ushort wLanguage, byte[] lpData, uint cbData);

    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "UpdateResourceW", CharSet = CharSet.Unicode)]
    private static extern bool UpdateResourceString(IntPtr hUpdate, IntPtr lpType, string lpName, ushort wLanguage, byte[] lpData, uint cbData);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool EnumResourceNames(IntPtr hModule, IntPtr lpszType, EnumResourceNamesProc lpEnumFunc, IntPtr lParam);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool EnumResourceLanguages(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, EnumResourceLanguagesProc lpEnumFunc, IntPtr lParam);

    private sealed class GroupIconResource
    {
        public bool IsInteger;
        public ushort Id;
        public string Name;
        public ushort Language;

        public string DisplayName
        {
            get { return IsInteger ? "#" + Id.ToString() : Name; }
        }
    }

    private sealed class IconImage
    {
        public byte Width;
        public byte Height;
        public byte ColorCount;
        public byte Reserved;
        public ushort Planes;
        public ushort BitCount;
        public uint BytesInRes;
        public byte[] Bytes;
        public ushort ResourceId;
    }

    private static IntPtr MakeIntResource(ushort value)
    {
        return new IntPtr(value);
    }

    private static bool IsIntResource(IntPtr value)
    {
        return ((ulong)value.ToInt64() >> 16) == 0;
    }

    private static ushort IntResourceId(IntPtr value)
    {
        return unchecked((ushort)value.ToInt64());
    }

    private static string PtrToResourceName(IntPtr value)
    {
        if (IsIntResource(value))
        {
            return null;
        }
        return Marshal.PtrToStringUni(value);
    }

    private static ushort ReadUInt16(byte[] bytes, int offset)
    {
        return BitConverter.ToUInt16(bytes, offset);
    }

    private static uint ReadUInt32(byte[] bytes, int offset)
    {
        return BitConverter.ToUInt32(bytes, offset);
    }

    private static List<IconImage> ReadIconFile(string iconPath)
    {
        byte[] bytes = File.ReadAllBytes(iconPath);
        if (bytes.Length < 6)
        {
            throw new InvalidDataException("ICO file is too small: " + iconPath);
        }
        if (ReadUInt16(bytes, 0) != 0 || ReadUInt16(bytes, 2) != 1)
        {
            throw new InvalidDataException("ICO file has an invalid header: " + iconPath);
        }

        ushort count = ReadUInt16(bytes, 4);
        if (count == 0)
        {
            throw new InvalidDataException("ICO file does not contain images: " + iconPath);
        }
        if (bytes.Length < 6 + (count * 16))
        {
            throw new InvalidDataException("ICO directory is truncated: " + iconPath);
        }

        var images = new List<IconImage>();
        for (int index = 0; index < count; index++)
        {
            int entryOffset = 6 + (index * 16);
            uint size = ReadUInt32(bytes, entryOffset + 8);
            uint imageOffset = ReadUInt32(bytes, entryOffset + 12);
            if (size == 0 || imageOffset > bytes.Length || imageOffset + size > bytes.Length)
            {
                throw new InvalidDataException("ICO image entry is outside file bounds: " + iconPath);
            }

            byte[] imageBytes = new byte[size];
            Buffer.BlockCopy(bytes, (int)imageOffset, imageBytes, 0, (int)size);
            images.Add(new IconImage {
                Width = bytes[entryOffset],
                Height = bytes[entryOffset + 1],
                ColorCount = bytes[entryOffset + 2],
                Reserved = bytes[entryOffset + 3],
                Planes = ReadUInt16(bytes, entryOffset + 4),
                BitCount = ReadUInt16(bytes, entryOffset + 6),
                BytesInRes = size,
                Bytes = imageBytes,
                ResourceId = (ushort)(index + 1)
            });
        }

        return images;
    }

    private static byte[] BuildGroupIconData(List<IconImage> images)
    {
        using (var stream = new MemoryStream())
        using (var writer = new BinaryWriter(stream))
        {
            writer.Write((ushort)0);
            writer.Write((ushort)1);
            writer.Write((ushort)images.Count);

            foreach (IconImage image in images)
            {
                writer.Write(image.Width);
                writer.Write(image.Height);
                writer.Write(image.ColorCount);
                writer.Write(image.Reserved);
                writer.Write(image.Planes);
                writer.Write(image.BitCount);
                writer.Write(image.BytesInRes);
                writer.Write(image.ResourceId);
            }

            return stream.ToArray();
        }
    }

    private static List<GroupIconResource> GetGroupIconResources(string exePath)
    {
        IntPtr module = LoadLibraryEx(exePath, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE);
        if (module == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "LoadLibraryEx failed for " + exePath);
        }

        var groups = new List<GroupIconResource>();
        try
        {
            EnumResourceNamesProc nameProc = delegate(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, IntPtr lParam)
            {
                bool isInteger = IsIntResource(lpszName);
                ushort id = isInteger ? IntResourceId(lpszName) : (ushort)0;
                string name = isInteger ? null : PtrToResourceName(lpszName);

                EnumResourceLanguagesProc langProc = delegate(IntPtr hModule2, IntPtr lpszType2, IntPtr lpszName2, ushort language, IntPtr lParam2)
                {
                    groups.Add(new GroupIconResource {
                        IsInteger = isInteger,
                        Id = id,
                        Name = name,
                        Language = language
                    });
                    return true;
                };

                if (!EnumResourceLanguages(hModule, MakeIntResource(RT_GROUP_ICON), lpszName, langProc, IntPtr.Zero))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "EnumResourceLanguages failed for group icon resource");
                }
                return true;
            };

            if (!EnumResourceNames(module, MakeIntResource(RT_GROUP_ICON), nameProc, IntPtr.Zero))
            {
                int error = Marshal.GetLastWin32Error();
                if (error != ERROR_RESOURCE_TYPE_NOT_FOUND)
                {
                    throw new Win32Exception(error, "EnumResourceNames failed for group icon resources");
                }
            }
        }
        finally
        {
            FreeLibrary(module);
        }

        if (groups.Count == 0)
        {
            groups.Add(new GroupIconResource {
                IsInteger = true,
                Id = 1,
                Name = null,
                Language = 0
            });
        }

        return groups;
    }

    private static void ThrowLastWin32(string message)
    {
        throw new Win32Exception(Marshal.GetLastWin32Error(), message);
    }

    public static string SetIcon(string exePath, string iconPath)
    {
        List<IconImage> images = ReadIconFile(iconPath);
        byte[] groupData = BuildGroupIconData(images);
        List<GroupIconResource> groups = GetGroupIconResources(exePath);

        IntPtr update = BeginUpdateResource(exePath, false);
        if (update == IntPtr.Zero)
        {
            ThrowLastWin32("BeginUpdateResource failed for " + exePath);
        }

        bool committed = false;
        try
        {
            foreach (GroupIconResource group in groups)
            {
                foreach (IconImage image in images)
                {
                    if (!UpdateResourceInt(update, MakeIntResource(RT_ICON), MakeIntResource(image.ResourceId), group.Language, image.Bytes, (uint)image.Bytes.Length))
                    {
                        ThrowLastWin32("UpdateResource failed for icon image #" + image.ResourceId.ToString() + " language " + group.Language.ToString());
                    }
                }

                bool groupUpdated = group.IsInteger
                    ? UpdateResourceInt(update, MakeIntResource(RT_GROUP_ICON), MakeIntResource(group.Id), group.Language, groupData, (uint)groupData.Length)
                    : UpdateResourceString(update, MakeIntResource(RT_GROUP_ICON), group.Name, group.Language, groupData, (uint)groupData.Length);
                if (!groupUpdated)
                {
                    ThrowLastWin32("UpdateResource failed for group icon " + group.DisplayName + " language " + group.Language.ToString());
                }
            }

            if (!EndUpdateResource(update, false))
            {
                ThrowLastWin32("EndUpdateResource failed for " + exePath);
            }
            committed = true;
            return groups.Count.ToString();
        }
        finally
        {
            if (!committed)
            {
                EndUpdateResource(update, true);
            }
        }
    }
}
"@
}

$resolvedExe = (Resolve-Path -LiteralPath $ExePath).Path
$resolvedIcon = (Resolve-Path -LiteralPath $IconPath).Path
$updatedGroups = [YukinoExecutableIconResourceUpdater]::SetIcon($resolvedExe, $resolvedIcon)
Write-Host "Patched executable icon resource group(s): $updatedGroups"
