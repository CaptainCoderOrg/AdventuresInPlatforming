<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.11.2" name="enemy_spawns" tilewidth="48" tileheight="32" tilecount="12" columns="0">
 <editorsettings>
  <export target="enemy_spawns.lua" format="lua"/>
 </editorsettings>
 <grid orientation="orthogonal" width="1" height="1"/>
 <tile id="0">
  <properties>
   <property name="key" value="guardian"/>
   <property name="offset_x" type="float" value="-1"/>
   <property name="offset_y" type="float" value="1"/>
   <property name="type" value="enemy"/>
  </properties>
  <image source="enemies/guardian.png" width="48" height="32"/>
 </tile>
 <tile id="1">
  <properties>
   <property name="key" value="magician"/>
   <property name="type" value="enemy"/>
  </properties>
  <image source="enemies/magician.png" width="16" height="16"/>
 </tile>
 <tile id="2">
  <properties>
   <property name="key" value="ratto"/>
   <property name="offset_x" type="float" value="0"/>
   <property name="offset_y" type="float" value="0.5"/>
   <property name="type" value="enemy"/>
  </properties>
  <image source="enemies/ratto.png" width="16" height="8"/>
 </tile>
 <tile id="3">
  <properties>
   <property name="key" value="spike_slug"/>
   <property name="offset_x" type="float" value="0"/>
   <property name="offset_y" type="float" value="0"/>
   <property name="type" value="enemy"/>
  </properties>
  <image source="enemies/spikeslig.png" width="16" height="16"/>
 </tile>
 <tile id="4">
  <properties>
   <property name="key" value="worm"/>
   <property name="offset_x" type="float" value="0"/>
   <property name="offset_y" type="float" value="0"/>
   <property name="type" value="enemy"/>
  </properties>
  <image source="enemies/worm.png" width="16" height="8"/>
 </tile>
 <tile id="5">
  <properties>
   <property name="key" value="zombie"/>
   <property name="type" value="enemy"/>
  </properties>
  <image source="enemies/zombie.png" width="16" height="16"/>
 </tile>
 <tile id="6">
  <properties>
   <property name="key" value="bat_eye"/>
   <property name="type" value="enemy"/>
  </properties>
  <image source="enemies/bateye.png" width="16" height="16"/>
 </tile>
 <tile id="7">
  <properties>
   <property name="key" value="ghost_painting"/>
   <property name="offset_y" type="float" value="0"/>
   <property name="type" value="enemy"/>
  </properties>
  <image source="enemies/ghost_painting.png" width="16" height="24"/>
 </tile>
 <tile id="8" x="0" y="0" width="18" height="26">
  <properties>
   <property name="key" value="flaming_skull"/>
   <property name="offset_y" type="float" value="0"/>
   <property name="speed" type="float" value="2"/>
   <property name="start_direction" value="NE"/>
   <property name="type" value="enemy"/>
  </properties>
  <image source="../assets/sprites/enemies/flaming_skull/flaming_skull.png" width="144" height="26"/>
 </tile>
 <tile id="9" x="0" y="0" width="16" height="16">
  <properties>
   <property name="flip" type="bool" value="true"/>
   <property name="key" value="blue_slime"/>
   <property name="type" value="enemy"/>
  </properties>
  <image source="../assets/sprites/enemies/blue_slime/blue_slime_idle.png" width="80" height="16"/>
 </tile>
 <tile id="10" x="0" y="0" width="16" height="16">
  <properties>
   <property name="flip" type="bool" value="true"/>
   <property name="key" value="red_slime"/>
   <property name="type" value="enemy"/>
  </properties>
  <image source="../assets/sprites/enemies/red_slime/red_slime_idle.png" width="80" height="16"/>
 </tile>
 <tile id="11" x="0" y="0" width="16" height="16">
  <properties>
   <property name="flip" type="bool" value="true"/>
   <property name="key" value="gnomo_axe_thrower"/>
   <property name="type" value="enemy"/>
  </properties>
  <image source="../assets/sprites/enemies/gnomo/gnomo_idle.png" width="80" height="16"/>
 </tile>
</tileset>
