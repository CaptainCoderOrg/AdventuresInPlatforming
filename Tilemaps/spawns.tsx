<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.11.2" name="spawns" tilewidth="32" tileheight="32" tilecount="18" columns="0">
 <editorsettings>
  <export target="spawns.lua" format="lua"/>
 </editorsettings>
 <grid orientation="orthogonal" width="1" height="1"/>
 <tile id="1">
  <properties>
   <property name="flip" type="bool" value="true"/>
   <property name="gold" type="int" value="5"/>
   <property name="type" value="chest"/>
  </properties>
  <image source="objects/brown_chest.png" width="16" height="16"/>
 </tile>
 <tile id="17">
  <properties>
   <property name="flip" type="bool" value="false"/>
   <property name="gold" type="int" value="5"/>
   <property name="type" value="chest"/>
  </properties>
  <image source="objects/brown_chest_no_flip.png" width="16" height="16"/>
 </tile>
 <tile id="2">
  <properties>
   <property name="type" value="button"/>
  </properties>
  <image source="objects/button.png" width="16" height="16"/>
 </tile>
 <tile id="3">
  <properties>
   <property name="type" value="campfire"/>
  </properties>
  <image source="objects/campfire.png" width="16" height="16"/>
 </tile>
 <tile id="4">
  <properties>
   <property name="type" value="unique_item"/>
  </properties>
  <image source="objects/gold_key_spin.png" width="16" height="16"/>
 </tile>
 <tile id="5">
  <properties>
   <property name="type" value="ladder"/>
  </properties>
  <image source="objects/ladder_bottom.png" width="16" height="16"/>
 </tile>
 <tile id="6">
  <properties>
   <property name="type" value="ladder"/>
  </properties>
  <image source="objects/ladder_mid.png" width="16" height="16"/>
 </tile>
 <tile id="7">
  <properties>
   <property name="type" value="ladder"/>
  </properties>
  <image source="objects/ladder_top.png" width="16" height="16"/>
 </tile>
 <tile id="8">
  <properties>
   <property name="type" value="lever"/>
  </properties>
  <image source="objects/lever.png" width="16" height="16"/>
 </tile>
 <tile id="9">
  <properties>
   <property name="type" value="locked_door"/>
  </properties>
  <image source="objects/locked_door.png" width="16" height="32"/>
 </tile>
 <tile id="10">
  <properties>
   <property name="type" value="pressure_plate"/>
  </properties>
  <image source="objects/pressure_plate.png" width="32" height="16"/>
 </tile>
 <tile id="11">
  <properties>
   <property name="text" value="Undefined"/>
   <property name="type" value="sign"/>
  </properties>
  <image source="../assets/sprites/environment/sign.png" width="16" height="16"/>
 </tile>
 <tile id="12">
  <properties>
   <property name="type" value="speark_trap"/>
  </properties>
  <image source="objects/spear_trap.png" width="16" height="16"/>
 </tile>
 <tile id="13">
  <properties>
   <property name="type" value="spike_trap"/>
  </properties>
  <image source="objects/spikes-retract.png" width="16" height="16"/>
 </tile>
 <tile id="14">
  <properties>
   <property name="type" value="stairs"/>
  </properties>
  <image source="objects/stairs_up.png" width="32" height="32"/>
 </tile>
 <tile id="15">
  <properties>
   <property name="type" value="trap_door"/>
  </properties>
  <image source="objects/trap_door.png" width="32" height="16"/>
 </tile>
 <tile id="16">
  <properties>
   <property name="offset_y" type="float" value="0"/>
   <property name="type" value="decoy_painting"/>
  </properties>
  <image source="enemies/ghost_painting.png" width="16" height="24"/>
 </tile>
 <tile id="18" x="0" y="0" width="32" height="32">
  <properties>
   <property name="state" value="opened"/>
   <property name="type" value="boss_door"/>
  </properties>
  <image source="../assets/sprites/environment/boss_door.png" width="224" height="96"/>
 </tile>
</tileset>
