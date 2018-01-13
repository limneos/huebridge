# huebridge
Command line tool for controlling Philips Hue bridge and lights

# usage
    Options:

    Config:
      fullstate		Get full bridge state (dump)
      config		Get configuration
      deleteuser <name>	Delete user from whitelist

    Scenes:
      scenes		Get all scenes

    Groups:
      groups		Get all light groups
      group <groupNumber> <action> [value] (<action2> [value2]...)

    Lights:

      <lightNumber|lightName> <action> [value] (<action2> [value2]...)
      all <action> [value] (<action2> [value2]...)

  	    Action:	Value:			Description:
  	    get				Get light info
  	    on				Turn on light
  	    off				Turn off light
  	    toggle				Toggle light on/off
  	    hue	[0-65534]		Set Hue
  	    sat	[0-254]			Set Saturation
        bri	[0-254]			Set Brightness
        ct	[0-65534]		Set color temperature
        hue_inc	[-65534 to 65534]	Increase/decrease Hue
        sat_inc	[-245 to 254]		Increase/decrease Saturation
        bri_inc	[-245 to 254]		Increase/decrease Brightness
        ct_inc	[-65534 to 65534]	Increase/decrease ct
        alert	<none|select|lselect>	Set alert mode
        effect	<none|colorloop>	Set colorloop effect mode
        random				Set random color
        transitiontime	[0-36000]	Trasition delay x 100ms (10 is 1 second)
        <color>				Set color. Available colors:
          red,green,blue,orange,purple,pink,yellow,white,warmwhite
        coldwhite,lightblue,warmyellow,warmblue,maroon

        Groups only:
        scene	<sceneID>		Set scene to light group

    Advanced:

        -X <http method> '{"jsonkey":"jsonvalue"}' <urlpath>
      Sends a message body using given method (GET,POST,PUT,DELETE)
      e.g. huebridge -X PUT '{"on":true}' /lights/1/state
      More info: https://developers.meethue.com/documentation/lights-api

    Misc:

      clearSavedData			Resets this tool to its initial state

    Examples:

      huebridge all on			(Turn on all lights)
      huebridge 1 off			(Turn off light 1)
      huebridge KitchenLight off		(Turn off light named "KitchenLight")
      huebridge group 0 alert lselect	(Set all groups/lights to alerting)
      huebridge all bri 255 hue 23500 sat 180 transitiontime 10

# compile
You need Xcode to compile this.

To create a Mac OS binary:

    gcc -arch x86_64 -lstdc++ -isysroot $(xcrun --sdk macosx --show-sdk-path) -framework Foundation main.mm -o huebridge

To create a universal (FAT) binary (for iOS and Mac):


    gcc -arch x86_64 -lstdc++ -isysroot $(xcrun --sdk macosx --show-sdk-path) -framework Foundation main.mm -o hue.x86_64 &&  gcc  -lstdc++ -arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -framework Foundation main.mm -o hue.arm64 &&  gcc  -lstdc++ -arch armv7 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -framework Foundation main.mm -o hue.armv7 && lipo -arch armv7 hue.armv7 -arch arm64 hue.arm64 -arch x86_64 hue.x86_64 -create -o huebridge && ldid -S huebridge
    

# dependencies
- Xcode
- ldid (to sign for iOS) 

# todo

- Remove Foundation methods, use c-only libraries for string handling and json parsing, remove Xcode dependency.
- Clean up and make it a library, for embedding to other applications.
