<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.11.2" name="tileset_dungeon" tilewidth="16" tileheight="16" tilecount="63" columns="9">
 <editorsettings>
  <export target="tileset_dungeon.lua" format="lua"/>
 </editorsettings>
 <image source="../assets/Tilesets/tileset_dungeon.png" width="144" height="112"/>
 <tile id="0" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="1" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="2" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="4" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="5" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="6" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="9" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="10" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="11" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="13" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="15" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="17" type="bridge">
  <properties>
   <property name="type" value="bridge"/>
  </properties>
 </tile>
 <tile id="18" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="20" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="22" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="23" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="24" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="26" type="bridge">
  <properties>
   <property name="type" value="bridge"/>
  </properties>
 </tile>
 <tile id="27" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="29" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="35" type="bridge">
  <properties>
   <property name="type" value="bridge"/>
  </properties>
 </tile>
 <tile id="36" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="38" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="45" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="47" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="54" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="55" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <tile id="56" type="wall">
  <properties>
   <property name="type" value="wall"/>
  </properties>
 </tile>
 <wangsets>
  <wangset name="Dungeon Platforms" type="corner" tile="-1">
   <wangcolor name="Platform" color="#ff0000" tile="-1" probability="1"/>
   <wangcolor name="Not Platform" color="#00ff00" tile="-1" probability="1"/>
   <wangtile tileid="0" wangid="0,1,0,2,0,1,0,1"/>
   <wangtile tileid="1" wangid="0,1,0,2,0,2,0,1"/>
   <wangtile tileid="2" wangid="0,1,0,1,0,2,0,1"/>
   <wangtile tileid="9" wangid="0,2,0,2,0,1,0,1"/>
   <wangtile tileid="10" wangid="0,2,0,2,0,2,0,2"/>
   <wangtile tileid="11" wangid="0,1,0,1,0,2,0,2"/>
   <wangtile tileid="18" wangid="0,2,0,2,0,2,0,1"/>
   <wangtile tileid="20" wangid="0,1,0,2,0,2,0,2"/>
   <wangtile tileid="27" wangid="0,2,0,1,0,1,0,1"/>
   <wangtile tileid="29" wangid="0,1,0,1,0,1,0,2"/>
   <wangtile tileid="36" wangid="0,2,0,2,0,1,0,2"/>
   <wangtile tileid="38" wangid="0,2,0,1,0,2,0,2"/>
   <wangtile tileid="55" wangid="0,2,0,1,0,1,0,2"/>
  </wangset>
 </wangsets>
</tileset>
