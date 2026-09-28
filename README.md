# **Echo VR ArcPatcher**

Echo VR ArcPatcher is a script that utilises a few tools to dump and patch Echo VR's shaders so they can actually run on Intel Arc GPUs that do not support Vulkan's `shaderFloat64` feature.  
*This is intended for Linux systems. This does not currently support Windows!*

 **So... what does it do exactly?**  
Long story short, it dumps shaders using `vkd3d-proton` and then uses spirv-tools to disassemble, patch some areas to use *FP32* rather than FP64, and then reassemble those shaders into a folder that is then used to override Echo VR's vanilla shaders.    
For more information, refer to the Questions & Answers at the bottom of this README.
  
 **Mini Disclaimer**  
While this script does make it easier, it is still more involved at the moment as you have to enter different areas of content within the game to compile more shaders. This is because Echo VR compiles shaders as they are needed rather than at launch. 
***
# ***THE SUPER COOL MAIN GUIDE!!!***
   **REQUIREMENTS**  
*A computer that uses an Intel Arc GPU, and operates using Linux*  
RiftLift with Echo VR already added and working up to the crash.  
*Debug logging* turned *ON* in RiftLift.  
`python3` and `spirv-tools` installed on your system.

**SETUP**    
Download and uncompress the tar or zip archive  
Make sure the `.sh` and `.py` files are in the *same directory as one another*.
Assuming you will be running in the extracted directory, run `chmod +x ./echovr-arcpatcher.sh` to ensure that the executed script is executable.

 **BASIC USAGE**    
This will be assuming that you will be running the script in the same directory.    

*Running the script itself*   
A1. I just wanna run it!   
   Simply running it as is should work!  
   `./echovr-arcpatcher.sh`    
   The terminal output will tell you where things are placed on your system.  
   The script will try to use `echo-vr` as the game's slug by default. If that slug is not found, it'll attempt to identify a single Echo VR-like entry in your RiftLift game list. If it still can't determine a slug, you can refer to A2 to provide your own slug to the script.   
A2. I would like to specify some things  
	If you're someone who likes to keep things organized your way, you haven't been forgotten!    
	`./echovr-arcpatcher.sh [slug] [max-launches]`  
	`[slug]` is what RiftLift uses to launch your game, which defaults to `echo-vr` if unspecified. If you installed the game manually, use what you applied when adding, or leave unspecified (or blank using *`""`*) to use the default value. *If you need help with finding your game's slug, refer to B1.*   
	`[max-launches]` determines how many times the script will launch Echo VR before stopping itself, which defaults to `25` if unspecified.

 **EXTRA GUIDES**  
B1. How exactly do I find my game's slug?  
	 Simple! Just run `riftlift list` in your preferred Terminal application. A list of your games should pop up, and their slugs should be listed. Game Slugs are typically lowercased with dashes in the place of spaces.  
  
    
**ADVANCED CONFIGS**  
*[W.I.P]*
  
  
***
# Possible Questions that I made up because I felt like it  

**Why exactly is this needed?**  
Intel Arc Alchemist cards *do not* support Vulkan's `shaderFloat64` feature. Some of Echo VR's shaders contain FP64 operations, including conversions such as bool-to-float conversions. These cause `vkd3d-proton` to reject the affected shaders on Arc, thus resulting in the game aborting.  
I am unsure whether Intel Arc Battlemage and later GPUs support `shaderFloat64`. This script was developed and tested using an Alchemist GPU (A380).
This patching process is still very experimental, it can and most likely will have some hiccups with varying hardware.      
  
**What exactly** ***does*** **ArcPatcher change in these shaders anyways?**  
ArcPatcher works with the SPIR-V shaders dumped by `vkd3d-proton`. It looks for shaders that use the `shaderFloat64` capability, then checks whether their use of FP64 appears simple enough to safely patch automatically. For shaders that pass these checks, ArcPatcher replaces the affected 64-bit floating-point type with a 32-bit floating-point type, removes the unneeded `shaderFloat64` capability and related declarations, and then reassembles the shader. The resulting assembled shader is then validated using `spirv-val` before being placed into the preferred override directory. Echo VR then uses the patched shader instead of it's original version thanks to `vkd3d-proton`'s `VKD3D_SHADER_OVERRIDE` variable. This allows the affected shaders to be accepted and executed on Intel Arc without requiring Vulkan's `shaderFloat64` capability.  
  
**Where does ArcPatcher store the dumped and patched shaders?**  
ArcPatcher normally stores dumped and patched shaders under `~/.local/state/echo-vr/shaders`. If that cannot be used, it will try `~/.local/share/echo-vr/shaders`, and if that fallback is not available, it will then try `~/Documents/echo-vr/shaders`. The exact location that has been selected is printed when the script is run.   
This location can also be changed by the user. ~~Refer to the Advanced Configs section in the guide if you want to learn more.~~ (W.I.P.)
    
      
**Why does my game keep reopening after crashing?**  
This is intended. Echo VR compiles shaders *on demand* rather than compiling all of them at launch. Each relaunch gives the game another opportunity to encounter shaders that have not yet been dumped and patched.
  
**I am running the script, or will be, what exactly am I expected to do?**  
Currently, you're expected to just enter areas of the game. Ensure your VR is connected, otherwise Echo VR will purposely fail because it cannot detect a VR session.   
In my personal testing, you can just sit there for a bit until the Main Menu finally opens with no crash. From there, I recommend you keep clicking the TUTORIAL button every time the game re-opens until the Tutorial eventually loads with no crash, After that, you should do the same but for the PLAY button until the Lobby loads with no crash. Arena *should* load with no issue after this, but Combat requires additional loading until it no longer crashes. 
  
**Why do I have to enter the Tutorial, Lobby, Combat Maps, etc.?**  
Echo VR compiles shaders on demand, ArcPatcher can only patch shaders after the game has already encountered and compiled them. Entering different areas of content in the game causes additional shaders to be compiled, which `vkd3d-proton` then dumps to the configured shader dump directory.
  
**Does this affect my actual game files? / Is it changing Echo VR's original game files?**  
*No*. The shaders are instead overridden using a different folder thanks to `vkd3d-proton`'s `VKD3D_SHADER_OVERRIDE` variable, but the game itself should stay intact.  
  
**What happens if a shader cannot be patched?**  
The script refuses to modify shaders when it detects FP64 usage that may be too complicated or unsafe for the patching process. When this happens, the script stops and identifies the shader that needs manual attention.   
This has not happened during my personal playtesting, but I felt it was a good safeguard to add anyways.
    
**How do I know when I'm done?**  
With the way this process is, there's no way for me to tell you where precisely you would be done, so this would have to be some testing on your end.  
If the game can reach areas you previously could not, you're done with those sections. If you can play the game for a solid amount of time with no crashes, it's reasonable to assume you're done patching.   
However, if you ever encounter a crash, you can always just run the script again! The shaders that are already patched will remain patched.  
  
**Can I stop the script and continue later?**  
Yes. Dumped and patched shaders are kept in the shader directory between runs. ArcPatcher scans the existing dump when it is run, so you can stop it and run it again tomorrow without restarting everything.   
(Unless you delete or move the shaders obviously.)
  
**Why do I need RiftLift's "Debug logging" option enabled?**  
Debug logging is required because the patcher uses the Proton log to detect FP64 shader warnings and which shader is problematic.  
    
**Does this work on all Intel Arc GPUs?**  
*Theoretically it should*, but that's *not* guaranteed. On my end, I have only tested this with an Intel Arc A380, the compatibility of other cards is unknown to me. Go for it though, no one's stopping you.  
  
**Why is the default launch limit 25?**  
Even though the amount of shaders probably exceeds 25, I set it to 25 as a safety measure to prevent annoying infinite error looping. This is directly tweakable though, so you can use whatever you see fit.  
If ArcPatcher reaches the specified launch limit, *nothing is lost* and you can simply run it again to resume.

**Does this have any downsides?**  
I haven't noticed any issues regarding graphics and gameplay. Just don't expect amazing performance if you have a lower-end Arc card like me, Echo VR itself is demanding like most VR titles. (This is not an issue with the patcher to my knowledge, this is just a skill issue on my hardware specs!!!)  
There's also the obvious downside that *this is not officially supported by Echo VR*! As you should with anything unofficial, expect potential unexpected behaviour.

**Does this support Windows?**  
*Not at this time.* This heavily relies on `vkd3d-proton` to dump and override shaders. I am unaware of any tools that can do this on Windows, and it would be a whole lot more involved than it already is. 
~~plus i don't like windows enough to care tbh...~~

  
    
   
***
#  **Other Info**    
  
**My Test Environment**    
**HARDWARE**:  
GPU = Intel Corporation DG2 [Arc A380]  
CPU = 12th Gen Intel(R) Core(TM) i3-12100F  
Motherboard = BIOSTAR Group B660MXC PRO  
RAM = 16 GiB DDR4 (15 GiB usable)  
HMD = Meta Quest 3S  
  
**SOFTWARE/OS**:  
OS = CachyOS  
Kernel = 7.2.6-1-cachyos  
WM = Hyprland  

**SOFTWARE/DRIVERS**:  
Package = mesa 3:26.2.3-1  
Package = vulkan-intel 3:26.2.3-1  
API Version = 1.4.354  
Driver Name = Intel open-source Mesa driver  
Driver Info = Mesa 26.2.3-arch3.1  

**SOFTWARE/UTILITY**
Python Version = Python 3.14.7  
SPIRV = SPIRV-Tools v2026.3 vulkan-sdk-1.4.357.0-0-g9a49b0883  

**SOFTWARE/VR**:  
RiftLift Version = riftlift 0.10.2.5  
WiVRn Version = Version 26.9  
WayVR Version = 26.8.0  
Proton Version = GE-Proton11-3  
DXVK Version = 3.0.2-riftlift.1  
vkd3d-proton Version = vkd3d-1.1-5438-g3dfc6f07d

**The main error from Proton's log**
`d3d12_device_validate_shader_meta: Attempting to use FP64 operations in shader [SHADERHASH], but this is not supported.`
