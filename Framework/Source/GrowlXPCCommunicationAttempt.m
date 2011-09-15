//
//  GrowlXPCCommunicationAttempt.m
//  Growl
//
//  Created by Rachel Blackman on 8/22/11.
//  Copyright 2011 The Growl Project. All rights reserved.
//

#import "GrowlXPCCommunicationAttempt.h"
#import "GrowlDefines.h"
#import "NSObject+XPCHelpers.h"

#import <xpc/xpc.h>

@implementation GrowlXPCCommunicationAttempt

+ (NSString*)XPCBundleID
{
   return [NSString stringWithFormat:@"%@.GNTPClientService", [[NSBundle mainBundle] bundleIdentifier]];
}

+ (BOOL)canCreateConnection
{
   static xpc_connection_t connect = NULL;
   
   if (xpc_connection_create == NULL)
      return NO;
   
   if(!connect){   
      connect = xpc_connection_create([[GrowlXPCCommunicationAttempt XPCBundleID] UTF8String], dispatch_get_main_queue());
      if(!connect)
         return NO;
   }
   return YES;
}

- (void)finished
{
   if(xpcConnection){
      xpc_release(xpcConnection);
      xpcConnection = NULL;
   }
   [super finished];
}

- (BOOL) establishConnection
{
    if (xpc_connection_create == NULL) {
        // We are not on Lion.  We can't do this.
        return NO;
    }
    
   __block GrowlXPCCommunicationAttempt *blockSafe = self;
    //Third party developers will need to make sure to rename the bundle, executable, and info.plist stuff to tld.company.product.GNTPClientService 
   xpcConnection = xpc_connection_create(/*"com.Growl.BeepHammer.GNTPClientService"*/[[GrowlXPCCommunicationAttempt XPCBundleID] UTF8String], dispatch_get_main_queue());
    if (!xpcConnection)
        return NO;
   xpc_connection_set_event_handler(xpcConnection, ^(xpc_object_t object) {
      xpc_type_t type = xpc_get_type(object);
      
      if (type == XPC_TYPE_ERROR) {
         
         if (object == XPC_ERROR_CONNECTION_INTERRUPTED) {
            NSLog(@"Interrupted connection to XPC service");
         } else if (object == XPC_ERROR_CONNECTION_INVALID) {
            NSString *errorDescription = [NSString stringWithUTF8String:xpc_dictionary_get_string(object, XPC_ERROR_KEY_DESCRIPTION)];
            NSLog(@"Connection Invalid error for XPC service (%@)", errorDescription);
            xpc_release(xpcConnection);
            xpcConnection = NULL;
            [blockSafe failed];
            [blockSafe finished];
         } else {
            NSLog(@"Unexpected error for XPC service");
         }
      } else {
         [blockSafe handleReply:object];
      }

   });
   xpc_connection_resume(xpcConnection);
    return YES;
}

- (void) handleReply:(xpc_object_t)reply
{
    // We received a reply, which will either be a 'success' marker 
    // for registration, or some horrific failure.  "Do or do not,
    // there is no try."
    
    xpc_type_t type = xpc_get_type(reply);
    
    if (XPC_TYPE_ERROR == type) {
        [self failed];
        return; 
    }
    
    if (XPC_TYPE_DICTIONARY != type) {
        [self failed];
        return;
    }
    
   NSDictionary *dict = [NSObject xpcObjectToNSObject:reply];
   NSLog(@"response dict: %@", dict);
   
   BOOL success = [[dict objectForKey:@"Success"] boolValue];
   
    if (success)
        [self succeeded];
    else
        [self failed];
}

- (BOOL) sendMessageWithPurpose:(NSString *)purpose andReplyHandler:(void (^)(xpc_object_t))handler
{
    if (!xpcConnection)
        return NO;
    
    xpc_object_t xpcMessage = xpc_dictionary_create(NULL, NULL, 0);
    
    // Add the known parameters, yay!
    xpc_dictionary_set_string(xpcMessage, "GrowlDictType", [purpose UTF8String]);
    
    xpc_object_t growlDict = [(NSObject*)self.dictionary newXPCObject];
    xpc_dictionary_set_value(xpcMessage, "GrowlDict", growlDict);
    xpc_release(growlDict);
    
    if (handler) {
       xpc_connection_send_message_with_reply(self->xpcConnection, xpcMessage, dispatch_get_main_queue(), handler);
    }else{
       xpc_connection_send_message(xpcConnection, xpcMessage);
    }
    xpc_release(xpcMessage);
    
    return YES;
}

- (BOOL) sendMessageWithPurpose:(NSString *)purpose
{
    return [self sendMessageWithPurpose:purpose andReplyHandler:nil];
}

@end
