#include <stdlib.h>  
#include <arpa/inet.h>
#include <sys/socket.h> 
#include <Foundation/Foundation.h>

static BOOL isGroupData=NO;
static char *execPath=NULL;
static int totalRequests=0;
static NSString *BRIDGEIP=NULL;
static NSString *USERNAME=NULL;
typedef void(^boolBlock)(BOOL);

@interface Connection : NSObject 
@end

#define BRIDGEADDRESS [NSString stringWithFormat:@"http://%@/api/%@",BRIDGEIP,USERNAME]


@implementation NSMutableArray (lim)
-(void)_m_removeFirstObject{
	if ([self count]>0){
		[self removeObjectAtIndex:0];
	}
}
@end

@implementation NSString (lim)
-(BOOL)equalsci:(NSString *)substring{ // case insensitive compare
	return [self rangeOfString:substring options:NSCaseInsensitiveSearch].location==0 && [self length]==[substring length];
}
@end


unsigned long randr(unsigned long min, unsigned long max){

	unsigned long r = ( rand() % max) +  min;
	if (r>max){
		r=r-min;
	}
	return r;

}

// Perform SSDP discovery (UDP) for Hue Bridges and find the ip address
const char * discoverHueIp(){
	
	struct sockaddr_in si_me, si_other;
     
    int s, i, slen = sizeof(si_other) , recv_len;
    char buf[512]; //max buff len
     
    if ((s=socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)) == -1) {
        printf("Discover IP: no socket\n");
        exit(1);
    }
     
    memset((char *) &si_me, 0, sizeof(si_me));
     
    si_me.sin_family = AF_INET;
    si_me.sin_port = htons(0); //listen to port 0 for incoming data
    si_me.sin_addr.s_addr = inet_addr("0.0.0.0");
	
    si_other.sin_family = AF_INET;
    si_other.sin_port = htons(1900);
    si_other.sin_addr.s_addr = inet_addr("239.255.255.250");
	
    if( bind(s , (struct sockaddr*)&si_me, sizeof(si_me) ) == -1)
    {
        printf("Discover IP: no bind\n");
        exit(1);
    }
    
    const char *data = "M-SEARCH * HTTP/1.1\r\n" \
        "Host: 239.255.255.250:1900\r\n" \
        "ST: urn:schemas-upnp-org:device:basic:1\r\n" \
        "MAN: \"ssdp:discover\"\r\n" \
        "MX: 5\r\n" \
        "\r\n";

    NSTimeInterval startTime=CFAbsoluteTimeGetCurrent();
        
    sendto(s, data, strlen(data), 0, (struct sockaddr*) &si_other, slen);
    
    NSMutableArray *ipsFound=[[NSMutableArray alloc] init];

    while(1){
        
        fflush(stdout);

        if ((recv_len = recvfrom(s, buf, 512, 0, (struct sockaddr *) &si_other, (socklen_t *)&slen)) == -1){
            printf("Discover IP: no recvfrom()\n");
            exit(1);
        }
         
        if (strstr(buf,"IpBridge")){
        	//printf("\nReceived packet from %s:%d\n", inet_ntoa(si_other.sin_addr), ntohs(si_other.sin_port));
	        //printf("Data: %s\n" , buf);
	        const char *ipaddress=inet_ntoa(si_other.sin_addr);
			close(s);
			return ipaddress;
        }
        
    }
 
    close(s);
    return NULL;
}




@implementation Connection {

	NSMutableDictionary* lightInfo;
	
}

-(id)init{
	
	if (self=[super init]){
		
		NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:@"net.limneos.huebridge"];
		[defaults synchronize];
		
		BRIDGEIP=[defaults objectForKey:@"bridgeip"];
		if (!BRIDGEIP){
			BRIDGEIP=[NSString stringWithUTF8String:discoverHueIp()];
			if (!BRIDGEIP){ 
				NSData *ipResult=[NSData dataWithContentsOfURL:[NSURL URLWithString:@"http://www.meethue.com/api/nupnp"]];
				NSError *error=NULL;
				NSArray * newJson = [NSJSONSerialization JSONObjectWithData:ipResult options:kNilOptions error:&error];
				BRIDGEIP=[(NSDictionary *)[newJson firstObject] objectForKey:@"internalipaddress"];
			}
			if (!BRIDGEIP){
				printf("Unable to automatically detect bridge's ip address.\nPlease enter bridge ip address: ");
				char inip[20];
				gets(inip);
				BRIDGEIP=[NSString stringWithUTF8String:inip];
			}
			[defaults setObject:BRIDGEIP forKey:@"bridgeip"];
			[defaults synchronize];
		}
		
		[BRIDGEIP retain];
		
		USERNAME=[[defaults objectForKey:@"username"] retain];
		
		if (!USERNAME){
			// first time ran
			printf("No username found for this app.\nPlease press the authenticate button on the bridge and then press enter: ");
			getchar();
			[Connection authenticateToBridge]; //will block until we get a username
			
		}
		[defaults release];
	}
	return self;

}

+(NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)responsePtr error:(NSError **)errorPtr {  

    dispatch_semaphore_t sem;  
    __block NSData *result;  
    result = NULL;  
	sem = dispatch_semaphore_create(0);  
 
  	[[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {  
        if (errorPtr != NULL) {  
            *errorPtr = error;  
        }  
        if (responsePtr != NULL) {  
            *responsePtr = response;  
        }  
        if (!error) {  
            result = [data retain];  

        }  
        dispatch_semaphore_signal(sem);  
    }] resume];  
 
	dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);  
	
   	return result;  
 
 
} 
+(void)authenticateToBridge{
	
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: [NSURL URLWithString:[NSString stringWithFormat:@"http://%@/api",BRIDGEIP] ] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:8];	
	[request setHTTPMethod:@"POST"];
	[request setValue:@"text/plain; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
	NSError *error=NULL;
	NSData* jsonData = [NSJSONSerialization dataWithJSONObject:@{@"devicetype":@"huebridge"} options:NSJSONWritingPrettyPrinted error:&error];
	if (error) {
		printf("Error creating json send data: %s\n",[[error description] UTF8String]);
		exit(1);
	}
	[request setHTTPBody:jsonData ];
	jsonData = [Connection sendSynchronousRequest:request returningResponse:NULL error:NULL];
	NSArray * jsonResult = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&error];
	[jsonData release];
	NSLog(@"jsonresult %@",jsonResult);
	if (error) {
		printf("Error parsing json receive data: %s\n",[[error description] UTF8String]);
		exit(1);
	}
	USERNAME=[[[jsonResult firstObject] objectForKey:@"success"] objectForKey:@"username"];
	
	NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:@"net.limneos.huebridge"];
	[defaults setObject:USERNAME forKey:@"username"];
	[defaults synchronize];
	[defaults release];
	[USERNAME retain];
	
	//NSLog(@"GOT USERNAME %@",USERNAME);
	if (!USERNAME){
		printf("No username found for this app.\nPlease press the authenticate button on the bridge and then press enter: ");
		getchar();
		[Connection authenticateToBridge];
	}

}
-(NSMutableDictionary *)lightInfo{
	return lightInfo;
}
-(void)getDataFromBridgeWithCompletion:(boolBlock)completion isGroupData:(BOOL)isGroup{


	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@",BRIDGEADDRESS, isGroup ? @"groups" : @"lights"]] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:8];
	//_connection = [[NSURLConnection alloc] initWithRequest:request  delegate:self startImmediately: YES] ;
	
	NSURLSessionDataTask *dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error){
		if (error){
    		printf("Request Error: %s\n",[[error description] UTF8String]);
    	}
    	lightInfo = [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error] retain];
    	if (error){
    		printf("Could not get data from bridge. Json Serialization Error: %s\n",[[error description] UTF8String]);
    		exit(1);
    	}
    	//printf("Data from bridge %s",[[json description] UTF8String]);
    	
		if (completion){
			completion(isGroup);
		}
    }];
	[dataTask resume];
	
}

-(void)turnOnAllLights{
	[self performRequest:@{@"on":@true} toPath:@"groups/0/action"]; // apart from user light groups (1,2 etc) , group "0" is a special group that means "all registered lights"
}
-(void)turnOffAllLights{
	[self performRequest:@{@"on":@false} toPath:@"groups/0/action"]; 
} 
-(void)setLightOrGroup:(int)lightNumber toState:(NSMutableDictionary *)state{
	[self performRequest:state toPath:[NSString stringWithFormat:isGroupData ? @"groups/%d/action" : @"lights/%d/state",lightNumber]];
}
-(void)dumpFullState{
	[self performRequest:NULL toPath:@"" method:@"GET"];
}
-(void)getConfig{
	[self performRequest:NULL toPath:@"config" method:@"GET"];
}
-(void)getGroups{
	[self performRequest:NULL toPath:@"groups" method:@"GET"];
}
-(void)getScenes{
	[self performRequest:NULL toPath:@"scenes" method:@"GET"];
}
-(void)deleteUser:(NSString *)user{
	[self performRequest:NULL toPath:[NSString stringWithFormat:@"config/whitelist/%@",user] method:@"DELETE"];
}
-(void)performRequest:(NSDictionary*)requestDict toPath:(NSString *)path{
 	[self performRequest:requestDict toPath:path method:@"PUT"];
}

-(void)performRequest:(NSDictionary*)requestDict toPath:(NSString *)path method:(NSString *)method{
	
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@",BRIDGEADDRESS,path]] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:8];	

	
	[request setHTTPMethod:method];
	[request setValue:@"text/plain; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

	if (requestDict){
		NSError *error=NULL;
		NSData* jsonData = [NSJSONSerialization dataWithJSONObject:requestDict options:NSJSONWritingPrettyPrinted error:&error];
		if (error) printf("Error creating json data: %s\n",[[error description] UTF8String]);
		[request setHTTPBody:jsonData ];
	}
	
	totalRequests++;
	
	NSURLSessionDataTask *dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *inData, NSURLResponse *response, NSError *error){
		if (error){
			printf("Request error: %s\n",[[error description] UTF8String]);
		}
		error=NULL;

		id jsonResult = [NSJSONSerialization JSONObjectWithData:inData options:NSJSONReadingMutableContainers error:NULL];

		if (error){
			printf("Json Serialization Error: %s\n",[[error description] UTF8String]);
		}
	 	
	 	NSString *resultStr=[jsonResult description];
	 	 
		if (resultStr){
			printf("%s\n",[resultStr UTF8String]);
		}

		totalRequests--;
		if (totalRequests==0){
			exit(0);
		}
	
    }];
 	[dataTask resume];
	 
	
}
 
@end


void printTinyUsage(){

	printf("usage: %s <all | lightNumber | [group [number]]> <action> [value]\n",execPath);
	printf("usage: %s <command> \n",execPath);
	printf("use --help for details\n");

}

void printUsage(){

	printf("usage: %s <lightNumber | lightName | all> <action> [value]\n",execPath);
	
	printf("Options:\n"
		"\nConfig:\n"
		"  fullstate\t\tGet full bridge state (dump)\n"
		"  config\t\tGet configuration\n"
		"  deleteuser <name>\tDelete user from whitelist\n\n"
		"Scenes:\n"
		"  scenes\t\tGet all scenes\n\n"
		"Groups:\n"
		"  groups\t\tGet all light groups\n"
		"  group <groupNumber> <action> [value] (<action2> [value2]...)\n\n"
		"Lights:\n\n"
		"  <lightNumber|lightName> <action> [value] (<action2> [value2]...)\n"
		"  all <action> [value] (<action2> [value2]...)\n\n"
		"  \tAction:\tValue:\t\t\tDescription:\n"
		"  \tget\t\t\t\tGet light info\n"
		"  \ton\t\t\t\tTurn on light\n"
		"  \toff\t\t\t\tTurn off light\n"
		"  \ttoggle\t\t\t\tToggle light on/off\n"
		"  \thue\t[0-65534]\t\tSet Hue\n"
		"  \tsat\t[0-254]\t\t\tSet Saturation\n"
		"  \tbri\t[0-254]\t\t\tSet Brightness\n"
		"  \tct\t[0-65534]\t\tSet color temperature\n"
		"  \thue_inc\t[-65534 to 65534]\tIncrease/decrease Hue\n"
		"  \tsat_inc\t[-245 to 254]\t\tIncrease/decrease Saturation\n"
		"  \tbri_inc\t[-245 to 254]\t\tIncrease/decrease Brightness\n"
		"  \tct_inc\t[-65534 to 65534]\tIncrease/decrease ct\n"
		"  \talert\t<none|select|lselect>\tSet alert mode\n"
		"  \teffect\t<none|colorloop>\tSet colorloop effect mode\n"
		"  \trandom\t\t\t\tSet random color\n"
		"  \ttransitiontime\t[0-36000]\tTrasition delay x 100ms (10 is 1 second)\n"
		"  \t<color>\t\t\t\tSet color. Available colors:\n"
		"  \t  red,green,blue,orange,purple,pink,yellow,white,warmwhite\n\t  coldwhite,lightblue,warmyellow,warmblue,maroon\n\n"
		"  \tGroups only:\n"
		"  \tscene\t<sceneID>\t\tSet scene to light group\n\n"
		"Advanced:\n\n"
		"  \t-X <http method> '{\"jsonkey\":\"jsonvalue\"}' <urlpath>\n"
		"\tSends a message body using given method (GET,POST,PUT,DELETE)\n"
		"\te.g. huebridge -X PUT '{\"on\":true}' /lights/1/state\n"
		"\tMore info: https://developers.meethue.com/documentation/lights-api\n\n"
		"Misc:\n\n"
		"  clearSavedData\t\t\tResets this tool to its initial state\n\n"
		"Examples:\n\n"
		"  huebridge all on\t\t\t(Turn on all lights)\n"
		"  huebridge 1 off\t\t\t(Turn off light 1)\n"
		"  huebridge KitchenLight off\t\t(Turn off light named \"KitchenLight\")\n"
		"  huebridge group 0 alert lselect\t(Set all groups/lights to alerting)\n"
		"  huebridge all bri 255 hue 23500 sat 180 transitiontime 10\n"
		
	);
	printf("\n");
}
 

int main(int argc, char **argv, char **envp) {
	
	execPath=argv[0];
	srand(time(NULL));
	Connection *connection=[[Connection alloc] init];
	
	NSArray *arguments=[[NSProcessInfo processInfo] arguments];
	NSMutableArray *args=[arguments mutableCopy];
	[args removeObjectAtIndex:0];

	int argCount=[args count];

	
	if ([[args firstObject] isEqual:@"--help"]){
		printUsage();
		return 0;
	}
	
	if (argCount==1 && [[args firstObject] isEqual:@"fullstate"]){
		[connection dumpFullState];	
	}
	else if (argCount==1 && [[args firstObject] isEqual:@"config"]){
		[connection getConfig];
	}
	else if (argCount==1 && [[args firstObject] isEqual:@"groups"]){
		[connection getGroups];
	}
	else if (argCount==1 && [[args firstObject] isEqual:@"scenes"]){
		[connection getScenes];
	}
	else if (argCount==1 && [[args firstObject] isEqual:@"clearSavedData"]){
		NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:@"net.limneos.huebridge"];
		[defaults removePersistentDomainForName:@"net.limneos.huebridge"];
		[defaults synchronize];
		printf("All stored settings are now cleared.\n");
		exit(0);
	}
	
	else if (argCount<2){
		printTinyUsage();
		exit(1); // I must have at least a light and a state to set to it
	}
	else if (argCount==2 && [[args firstObject] isEqual:@"deleteuser"]){
		[connection deleteUser:[args lastObject]];
	}
	else if (argCount==2 && [[args firstObject] rangeOfString:@"all" options:NSCaseInsensitiveSearch].location==0 && [[args lastObject] rangeOfString:@"on" options:NSCaseInsensitiveSearch].location==0 ){
		[connection turnOnAllLights];
	}
	else if (argCount==2 && [[args firstObject] rangeOfString:@"all" options:NSCaseInsensitiveSearch].location==0 && [[args lastObject] rangeOfString:@"off" options:NSCaseInsensitiveSearch].location==0 ){
		[connection turnOffAllLights];
	}
	else if ([[args firstObject] isEqual:@"-X"]){
		if (argCount!=4){
			printTinyUsage();
			exit(1);
		}
		if (![[args objectAtIndex:1] isEqual:@"GET"] && ![[args objectAtIndex:1] isEqual:@"POST"] && ![[args objectAtIndex:1] isEqual:@"PUT"] && ![[args objectAtIndex:1] isEqual:@"DELETE"]){
			printTinyUsage();
			exit(1);
		}
		 
		NSString *method=[args objectAtIndex:1];
		NSString *dataStr=[args objectAtIndex:2];
		NSData *data=[dataStr dataUsingEncoding:NSUTF8StringEncoding]; 
		NSString *urlpath=[args objectAtIndex:3];
		if ([[urlpath substringToIndex:1] isEqual:@"/"]){
			urlpath=[urlpath substringFromIndex:1]; //strip first /
		}
		NSError *error=NULL;
		NSMutableDictionary * requestDict = [NSJSONSerialization JSONObjectWithData:data options: NSJSONReadingMutableContainers error:&error];
		if (error){
			printf("While parsing -d json body: %s\n",[[error description] UTF8String]);
			exit(1);
		}
		[connection performRequest:requestDict toPath:urlpath method:method];				
	}
	else {
		isGroupData=[[args firstObject] isEqual:@"group"];
		if (isGroupData){
			[args _m_removeFirstObject];
		}
		[connection getDataFromBridgeWithCompletion:^(BOOL isGroup){
			
			NSString *arg=[args firstObject];
			NSMutableArray *names=[NSMutableArray array];			
			NSMutableArray *values=[NSMutableArray array];
			
			if (![[connection lightInfo] isKindOfClass:[NSDictionary class]]){
				if ([[[connection lightInfo] description] rangeOfString:@"unauthorized user"].location!=NSNotFound){
					printf("We need to authenticate or create a user first.\n");
					exit(1);
				}
				printf("Error: %s\n",[[[connection lightInfo] description] UTF8String]);
				exit(1);
			}
			for (NSString *value in [[connection lightInfo] allKeys]){
				[values addObject:value];
				[names addObject:[[[connection lightInfo] objectForKey:value] objectForKey:@"name"] ?: value];
			}

			int light=0;
			if ([names containsObject:arg] || [values containsObject:arg] || [arg rangeOfString:@"all" options:NSCaseInsensitiveSearch].location==0 || (isGroup && [arg isEqual:@"0"])){
				if ([arg rangeOfString:@"all" options:NSCaseInsensitiveSearch].location==0){
					light=1000; //all
				}
				else{
					if ([values containsObject:arg] || (isGroup && [arg isEqual:@"0"])){
						light=[arg intValue];
					}
					else{
						light=[[values objectAtIndex:[names indexOfObject:arg]] intValue];
					}
				}
				[args _m_removeFirstObject];

			}
			else{
				printf("\r\nError: You must specify a valid light, group, or all lights first\r\n");
				exit(1);
			}

			
			// start creating dictionary
			
			NSMutableDictionary *state=[NSMutableDictionary dictionary];
			
			while ([args count]>0){			

				arg=[args firstObject];
				
				if ([arg equalsci:@"get"]){

					[args removeAllObjects];
					
					if (light==1000){
						printf("%s\n",[[[connection lightInfo] description] UTF8String]);
					}
					else{
						printf("%s\n",[[[[connection lightInfo] objectForKey:[NSString stringWithFormat:@"%d",light]] description ] UTF8String]);
					}

					exit(0);

				}

				if ([arg equalsci:@"toggle"]){

					 break;

				}
				
				if ([arg equalsci:@"on"]){
					[state setObject:[NSNumber numberWithBool:YES] forKey:@"on"];
					[args _m_removeFirstObject];

				}

				else if ([arg equalsci:@"off"]){
					[state setObject:[NSNumber numberWithBool:NO] forKey:@"on"];
					[args _m_removeFirstObject];

			
				}
				
				else if ([arg equalsci:@"red"] || [arg equalsci:@"green"] || [arg equalsci:@"blue"] || [arg equalsci:@"orange"] || [arg equalsci:@"purple"] || [arg equalsci:@"pink"] || [arg equalsci:@"yellow"] || [arg equalsci:@"white"] || [arg equalsci:@"warmwhite"] || [arg equalsci:@"coldwhite"] || [arg equalsci:@"lightblue"] || [arg equalsci:@"warmyellow"] || [arg equalsci:@"warmblue"] || [arg equalsci:@"maroon"]){
					[state setObject:[NSNumber numberWithInt:[arg equalsci:@"red"] ? 0 : ([arg equalsci:@"green"] ? 25500 : ([arg equalsci:@"orange"] ? 6034 : ([arg equalsci:@"purple"] ? 51034 : ([arg equalsci:@"pink"] ? 58000 : ([arg equalsci:@"yellow"] ? 20000 : ([arg equalsci:@"white"] ? 31000 : ([arg equalsci:@"warmwhite"] ? 22000 : ([arg equalsci:@"coldwhite"] ? 37000 : ([arg equalsci:@"lightblue"] ? 45983 : ([arg equalsci:@"warmyellow"] ? 13787 : ([arg equalsci:@"warmblue"] ? 46077 : ([arg equalsci:@"maroon"] ? 64223 : 46920))))))))))))] forKey:@"hue"];
					[state setObject:[NSNumber numberWithInt:[arg equalsci:@"warmwhite"] ? 150 :([arg equalsci:@"lightblue"] ? 249 : ([arg equalsci:@"warmyellow"] ? 241 :  ([arg equalsci:@"warmblue"] ? 210 : ([arg equalsci:@"maroon"] ? 223 : 254))))] forKey:@"sat"];
					[args _m_removeFirstObject];
            
				}

				else if ([arg equalsci:@"random"]){
					[state setObject:[NSNumber numberWithInt:randr(0,65535)] forKey:@"hue"];
					[state setObject:[NSNumber numberWithInt:randr(150,254)]  forKey:@"sat"];
					[args _m_removeFirstObject];

			
				}

				else if ([arg equalsci:@"hue"] || [arg equalsci:@"sat"] || [arg equalsci:@"bri"] || [arg equalsci:@"ct"] || [arg equalsci:@"transitiontime"] || [arg equalsci:@"hue_inc"]  || [arg equalsci:@"sat_inc"]  || [arg equalsci:@"bri_inc"]  || [arg equalsci:@"ct_inc"]){
					if ([arg isEqual:[args lastObject]] ){
						printf("\r\n%s needs a spaced int value following it\r\n",[arg UTF8String]);
						exit(0);
					}
					[args removeObject:arg];
					NSString *inValue=[args firstObject];
					[state setObject:[NSNumber numberWithInt:[inValue intValue]] forKey:arg];
					[args _m_removeFirstObject];


				}
				else if ([arg equalsci:@"alert"]){
					if ([arg isEqual:[args lastObject]] ){
						printf("\r\nAlert needs a value following it\r\n");
						exit(0);
					}
					[args removeObject:arg];
					NSString *inValue=[args firstObject];
					if (![inValue isEqual:@"none"] && ![inValue isEqual:@"select"] && ![inValue isEqual:@"lselect"]){
						printf("\r\nAlert accepts either \"none\", \"select\" or \"lselect\" values\r\n");
						exit(0);				
					}
					[state setObject:inValue forKey:@"alert"];
					[args _m_removeFirstObject];


				}
				else if ([arg equalsci:@"effect"]){
					if ([arg isEqual:[args lastObject]] ){
						printf("\r\nEffect needs a value following it\r\n");
						exit(0);
					}
					[args removeObject:arg];
					NSString *inValue=[args firstObject];
					if (![inValue isEqual:@"none"] && ![inValue isEqual:@"colorloop"]){
						printf("\r\nEffect accepts either \"none\" or \"colorloop\" values\r\n");
						exit(0);				
					}
					[state setObject:inValue forKey:@"effect"];
					[args _m_removeFirstObject];


				}
				else{
					
					printf("\r\nArgument \"%s\" is not valid as a first parameter\n",[arg UTF8String]);
					exit(0);
				
				}
			}
			
			if (light==1000){
				if ([arg equalsci:@"toggle"] || [arg equalsci:@"random"]){
					for (int i=1; i<values.count+1; i++){
						if ([arg equalsci:@"toggle"]){
							BOOL currentState=[[[connection lightInfo] valueForKeyPath:[NSString stringWithFormat:@"%d.state.on",i]] boolValue];
							[state setObject:[NSNumber numberWithBool:!currentState] forKey:@"on"];
						}
						else{
							[state setObject:[NSNumber numberWithInt:randr(0,65535)] forKey:@"hue"];
							[state setObject:[NSNumber numberWithInt:randr(150,254)]  forKey:@"sat"];			
						}
						[connection setLightOrGroup:i toState:state];
						usleep(50000);
					}
				}
				else{
					[connection performRequest:state toPath:@"groups/0/action"];				
				}
			}
			else{
				if ([arg equalsci:@"toggle"]){
					BOOL currentState=[[[connection lightInfo] valueForKeyPath:[NSString stringWithFormat:@"%d.state.on",light]] boolValue];
					[state setObject:[NSNumber numberWithBool:!currentState] forKey:@"on"];
				}
				[connection setLightOrGroup:light toState:state];				
			}
			 
			
		} isGroupData:isGroupData];
	}	
 
	[[NSRunLoop currentRunLoop] run];
}