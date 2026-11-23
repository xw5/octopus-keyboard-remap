# Regenerates the OctopusKeyRemap icon assets (same octopus-in-a-keycap
# family as OctopusKey, warm orange accent to tell the tools apart):
#   res/octopusremap.ico - multi-size icon embedded into the exe (via octopusremap.rc)
#   docs/icon.png        - 512px master used by the README
# Run from anywhere: powershell -File tools/make-icon.ps1
# Requires: Windows PowerShell 5+ (System.Drawing).
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
public static class IconDraw {
  static GraphicsPath RoundRect(float x, float y, float w, float h, float r) {
    GraphicsPath p = new GraphicsPath();
    float d = 2 * r;
    if (d > w) d = w;
    if (d > h) d = h;
    p.AddArc(x, y, d, d, 180, 90);
    p.AddArc(x + w - d, y, d, d, 270, 90);
    p.AddArc(x + w - d, y + h - d, d, d, 0, 90);
    p.AddArc(x, y + h - d, d, d, 90, 90);
    p.CloseFigure();
    return p;
  }
  public static Bitmap Draw(int s) {
    Bitmap bmp = new Bitmap(s, s);
    Graphics g = Graphics.FromImage(bmp);
    g.SmoothingMode = SmoothingMode.AntiAlias;
    float f = s / 512f;   // design fraction

    Color capBg  = Color.FromArgb(255, 28, 28, 36);
    Color capBd  = Color.FromArgb(255, 64, 64, 82);
    Color orange = Color.FromArgb(255, 232, 116, 59);
    Color white  = Color.FromArgb(255, 245, 245, 250);

    // keycap
    float m = 20 * f;
    float r = 96 * f;
    using (GraphicsPath cap = RoundRect(m, m, s - 2 * m, s - 2 * m, r)) {
      using (SolidBrush b = new SolidBrush(capBg)) g.FillPath(b, cap);
      using (Pen p = new Pen(capBd, 10 * f)) g.DrawPath(p, cap);
    }
    // subtle top highlight
    using (GraphicsPath hl = RoundRect(m + 14 * f, m + 14 * f, s - 2 * m - 28 * f, s * 0.30f, r * 0.8f)) {
      using (SolidBrush b = new SolidBrush(Color.FromArgb(14, 255, 255, 255))) g.FillPath(b, hl);
    }

    using (Pen leg = new Pen(orange, 34 * f)) {
      leg.StartCap = LineCap.Round;
      leg.EndCap = LineCap.Round;
      leg.LineJoin = LineJoin.Round;
      // four curled tentacles (left to right)
      g.DrawBezier(leg, 176 * f, 282 * f, 138 * f, 322 * f, 138 * f, 368 * f, 184 * f, 381 * f);
      g.DrawBezier(leg, 223 * f, 300 * f, 212 * f, 341 * f, 225 * f, 376 * f, 247 * f, 379 * f);
      g.DrawBezier(leg, 289 * f, 300 * f, 300 * f, 341 * f, 287 * f, 376 * f, 265 * f, 379 * f);
      g.DrawBezier(leg, 336 * f, 282 * f, 374 * f, 322 * f, 374 * f, 368 * f, 328 * f, 381 * f);
    }
    // head dome over the legs
    using (SolidBrush b = new SolidBrush(orange))
      g.FillEllipse(b, 151 * f, 140 * f, 210 * f, 190 * f);

    // eyes (only when large enough to be meaningful)
    if (s >= 48) {
      using (SolidBrush b = new SolidBrush(white)) {
        g.FillEllipse(b, 219 * f, 196 * f, 32 * f, 36 * f);
        g.FillEllipse(b, 261 * f, 196 * f, 32 * f, 36 * f);
      }
      using (SolidBrush b = new SolidBrush(capBg)) {
        g.FillEllipse(b, 230 * f, 208 * f, 14 * f, 16 * f);
        g.FillEllipse(b, 272 * f, 208 * f, 14 * f, 16 * f);
      }
    }
    g.Dispose();
    return bmp;
  }
}
'@

$root = Split-Path -Parent $PSScriptRoot
$resDir = Join-Path $root 'res'
$docDir = Join-Path $root 'docs'
New-Item -ItemType Directory -Force -Path $resDir | Out-Null
New-Item -ItemType Directory -Force -Path $docDir | Out-Null

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngs = @{}
foreach ($sz in $sizes) {
  $bmp = [IconDraw]::Draw($sz)
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $pngs[$sz] = $ms.ToArray()
  $bmp.Dispose()
}

# 512 master for docs
$master = [IconDraw]::Draw(512)
$master.Save((Join-Path $docDir 'icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$master.Dispose()

# assemble multi-size .ico (PNG-compressed entries, Vista+)
$icoPath = Join-Path $resDir 'octopusremap.ico'
$fs = [IO.File]::Create($icoPath)
$bw = New-Object IO.BinaryWriter($fs)
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
foreach ($sz in $sizes) {
  $data = $pngs[$sz]
  $b = if ($sz -ge 256) { 0 } else { $sz }
  $bw.Write([Byte]$b); $bw.Write([Byte]$b)      # width, height (0 = 256)
  $bw.Write([Byte]0); $bw.Write([Byte]0)        # palette, reserved
  $bw.Write([UInt16]1); $bw.Write([UInt16]32)   # planes, bpp
  $bw.Write([UInt32]$data.Length)
  $bw.Write([UInt32]$offset)
  $offset += $data.Length
}
foreach ($sz in $sizes) { $bw.Write($pngs[$sz]) }
$bw.Flush(); $bw.Close(); $fs.Close()
Write-Host "ico written: $((Get-Item $icoPath).Length) bytes; docs/icon.png ok"
