--  see OpenUxAS\src\Communications\LMCPObjectMessageSenderPipe.cpp

with UxAS.Common.String_Constant.Content_Type;
with UxAS.Common.String_Constant.LMCP_Network_Socket_Address;
use  UxAS.Common.String_Constant.LMCP_Network_Socket_Address;
with UxAS.Comms.Transport.Network_Name;
with UxAS.Comms.Transport.ZeroMQ_Socket_Configurations;

with AVTAS.LMCP.Factory;
with AVTAS.LMCP.ByteBuffers;  use AVTAS.LMCP.ByteBuffers;

with Ada.Strings.Unbounded;   use Ada.Strings.Unbounded;

package body UxAS.Comms.LMCP_Object_Message_Sender_Pipes is

   ------------------------
   -- Initialize_Publish --
   ------------------------

   procedure Initialize_Publish
     (This         : in out LMCP_Object_Message_Sender_Pipe;
      Source_Group : String;
      Entity_Id    : UInt32;
      Service_Id   : UInt32)
   is
   begin
      --  initializeZmqSocket(sourceGroup, entityId, serviceId, ZMQ_PUB,
      --                      UxAS::common::LMCPNetworkSocketAddress::strGetInProc_FromMessageHub(), true);
      This.Initialize_Zmq_Socket
        (Source_Group   => Source_Group,
         Entity_Id      => Entity_Id,
         Service_Id     => Service_Id,
         Zmq_SocketType => ZMQ.Sockets.PUB,
         Socket_Address => To_String (InProc_From_MessageHub),
         Is_Server      => True);
   end Initialize_Publish;

   ------------------------------
   -- Initialize_External_Push --
   ------------------------------

   procedure Initialize_External_Push
     (This                    : in out LMCP_Object_Message_Sender_Pipe;
      Source_Group            : String;
      Entity_Id               : UInt32;
      Service_Id              : UInt32;
      External_Socket_Address : String;
      Is_Server               : Boolean)
   is
   begin
      --  initializeZmqSocket(sourceGroup, entityId, serviceId, ZMQ_PUSH, externalSocketAddress, isServer);
      This.Initialize_Zmq_Socket
        (Source_Group   => Source_Group,
         Entity_Id      => Entity_Id,
         Service_Id     => Service_Id,
         Zmq_SocketType => ZMQ.Sockets.PUSH,
         Socket_Address => External_Socket_Address,
         Is_Server      => Is_Server);
   end Initialize_External_Push;

   -----------------------------
   -- Initialize_External_Pub --
   -----------------------------

   procedure Initialize_External_Pub
     (This                    : in out LMCP_Object_Message_Sender_Pipe;
      Source_Group            : String;
      Entity_Id               : UInt32;
      Service_Id              : UInt32;
      External_Socket_Address : String;
      Is_Server               : Boolean)
   is
   begin
      --  initializeZmqSocket(sourceGroup, entityId, serviceId, ZMQ_PUB, externalSocketAddress, isServer);
      This.Initialize_Zmq_Socket
        (Source_Group   => Source_Group,
         Entity_Id      => Entity_Id,
         Service_Id     => Service_Id,
         Zmq_SocketType => ZMQ.Sockets.PUB,
         Socket_Address => External_Socket_Address,
         Is_Server      => Is_Server);
   end Initialize_External_Pub;

   ---------------------
   -- Initialize_Push --
   ---------------------

   procedure Initialize_Push
     (This         : in out LMCP_Object_Message_Sender_Pipe;
      Source_Group : String;
      Entity_Id    : UInt32;
      Service_Id   : UInt32)
   is
   begin
      --  initializeZmqSocket(sourceGroup, entityId, serviceId, ZMQ_PUSH,
      --                      UxAS::common::LMCPNetworkSocketAddress::strGetInProc_ToMessageHub(), false);
      This.Initialize_Zmq_Socket
        (Source_Group   => Source_Group,
         Entity_Id      => Entity_Id,
         Service_Id     => Service_Id,
         Zmq_SocketType => ZMQ.Sockets.PUSH,
         Socket_Address => To_String (InProc_To_MessageHub),
         Is_Server      => False);
   end Initialize_Push;

   -----------------------
   -- Initialize_Stream --
   -----------------------

   procedure Initialize_Stream
     (This           : in out LMCP_Object_Message_Sender_Pipe;
      Source_Group   : String;
      Entity_Id      : UInt32;
      Service_Id     : UInt32;
      Socket_Address : String;
      Is_Server      : Boolean)
   is
   begin
      --  initializeZmqSocket(sourceGroup, entityId, serviceId, ZMQ_STREAM, socketAddress, isServer);
      This.Initialize_Zmq_Socket
        (Source_Group   => Source_Group,
         Entity_Id      => Entity_Id,
         Service_Id     => Service_Id,
         Zmq_SocketType => ZMQ.Sockets.STREAM,
         Socket_Address => Socket_Address,
         Is_Server      => Is_Server);
   end Initialize_Stream;

   ----------------------------
   -- Send_Broadcast_Message --
   ----------------------------

   procedure Send_Broadcast_Message
     (This    : in out LMCP_Object_Message_Sender_Pipe;
      Message : AVTAS.LMCP.Object.Object_Any)
   is
   begin
      --  std::string fullLMCPObjectTypeName = LMCPObject->getFullLMCPTypeName();
      --  sendLimitedCastMessage(fullLMCPObjectTypeName, std::move(LMCPObject));
      This.Send_LimitedCast_Message (Message.getFullLmcpTypeName, Message);
   end Send_Broadcast_Message;

   ------------------------------
   -- Send_LimitedCast_Message --
   ------------------------------

   --   void
   --   sendLimitedCastMessage(const std::string& castAddress, std::unique_ptr<AVTAS::LMCP::Object> LMCPObject);
   procedure Send_LimitedCast_Message
     (This         : in out LMCP_Object_Message_Sender_Pipe;
      Cast_Address : String;
      Message      : AVTAS.LMCP.Object.Object_Any)
   is
      --  AVTAS::LMCP::ByteBuffer* LMCPByteBuffer = AVTAS::LMCP::Factory::packMessage(LMCPObject.get(), true);
      Buffer  : constant ByteBuffer := AVTAS.LMCP.Factory.packMessage (Message, enableChecksum => True);
      --  std::string serializedPayload = std::string(reinterpret_cast<char*>(LMCPByteBuffer->array()), LMCPByteBuffer->capacity());
      Payload : constant String := Buffer.Raw_Bytes;
   begin
      --  m_transportSender->sendMessage
      --   (castAddress,
      --    UxAS::common::ContentType::LMCP(),
      --    LMCPObject->getFullLMCPTypeName(),
      --    std::move(serializedPayload));
      This.Sender.Send_Message
        (Address      => Cast_Address,
         Content_Type => UxAS.Common.String_Constant.Content_Type.LMCP,
         Descriptor   => Message.getFullLmcpTypeName,
         Payload      => Payload);
   end Send_LimitedCast_Message;

   -----------------------------
   -- Send_Serialized_Message --
   -----------------------------

   procedure Send_Serialized_Message
     (This    : in out LMCP_Object_Message_Sender_Pipe;
      Message : Addressed_Attributed_Message_Ref)
   is
   begin
      --  m_transportSender->sendAddressedAttributedMessage(std::move(serializedLMCPObject));
      This.Sender.Send_Addressed_Attributed_Message (Message);
   end Send_Serialized_Message;

   -----------------------------------
   -- Send_Shared_Broadcast_Message --
   -----------------------------------

   procedure Send_Shared_Broadcast_Message
     (This    : in out LMCP_Object_Message_Sender_Pipe;
      Message : AVTAS.LMCP.Object.Object_Any)
   is
   begin
      --  sendSharedLimitedCastMessage(LMCPObject->getFullLMCPTypeName(), LMCPObject);
      This.Send_Shared_LimitedCast_Message (Message.getFullLmcpTypeName, Message);
   end Send_Shared_Broadcast_Message;

   -------------------------------------
   -- Send_Shared_LimitedCast_Message --
   -------------------------------------

   procedure Send_Shared_LimitedCast_Message
     (This         : in out LMCP_Object_Message_Sender_Pipe;
      Cast_Address : String;
      Message      : AVTAS.LMCP.Object.Object_Any)
   is
      --  AVTAS::LMCP::ByteBuffer* LMCPByteBuffer = AVTAS::LMCP::Factory::packMessage(LMCPObject.get(), true);
      Buffer  : constant ByteBuffer := AVTAS.LMCP.Factory.packMessage (Message, enableChecksum => True);
      --  std::string serializedPayload = std::string(reinterpret_cast<char*>(LMCPByteBuffer->array()), LMCPByteBuffer->capacity());
      Payload : constant String := Buffer.Raw_Bytes;
   begin
      --  Note: this body is identical to the body of Send_LimitedCast_Message, per the C++ implementation
      --  TODO: see why

      --  m_transportSender->sendMessage
      --   (castAddress,
      --    UxAS::common::ContentType::LMCP(),
      --    LMCPObject->getFullLMCPTypeName(),
      --    std::move(serializedPayload));
      This.Sender.Send_Message
        (Address      => Cast_Address,
         Content_Type => UxAS.Common.String_Constant.Content_Type.LMCP,
         Descriptor   => Message.getFullLmcpTypeName,
         Payload      => Payload);
   end Send_Shared_LimitedCast_Message;

   ---------------
   -- Entity_Id --
   ---------------

   function Entity_Id
     (This : LMCP_Object_Message_Sender_Pipe)
      return UInt32
   is (This.Entity_Id);

   ----------------
   -- Service_Id --
   ----------------

   function Service_Id
     (This : LMCP_Object_Message_Sender_Pipe)
      return UInt32
   is (This.Service_Id);

   -------------------
   -- Set_Entity_Id --
   -------------------

   procedure Set_Entity_Id
     (This  : in out LMCP_Object_Message_Sender_Pipe;
      Value : UInt32)
   is
   begin
      This.Entity_Id := Value;
   end Set_Entity_Id;

   --------------------
   -- Set_Service_Id --
   --------------------

   procedure Set_Service_Id
     (This  : in out LMCP_Object_Message_Sender_Pipe;
      Value : UInt32)
   is
   begin
      This.Service_Id := Value;
   end Set_Service_Id;

   ---------------------------
   -- Initialize_Zmq_Socket --
   ---------------------------

   procedure Initialize_Zmq_Socket
     (This           : in out LMCP_Object_Message_Sender_Pipe;
      Source_Group   : String;
      Entity_Id      : UInt32;
      Service_Id     : UInt32;
      Zmq_SocketType : ZMQ.Sockets.Socket_Type;
      Socket_Address : String;
      Is_Server      : Boolean)
   is
      use UxAS.Comms.Transport.ZeroMQ_Socket_Configurations;

      --  int32_t zmqhighWaterMark{100000};
      Zmq_High_Water_Mark : constant := 100_000;

      zmqLMCPNetworkSendSocket : ZeroMq_Socket_Configuration;
   begin
      --  m_entityId = entityId;
      --  m_serviceId = serviceId;
      This.Entity_Id := Entity_Id;
      This.Service_Id := Service_Id;

      --  UxAS::communications::transport::ZeroMqSocketConfiguration
      --  zmqLMCPNetworkSendSocket(UxAS::communications::transport::NETWORK_NAME::zmqLMCPNetwork(),
      --                           socketAddress,
      --                           zmqSocketType,
      --                           isServer,
      --                           false,
      --                           zmqhighWaterMark,
      --                           zmqhighWaterMark);
      zmqLMCPNetworkSendSocket := Make
        (Network_Name            => UxAS.Comms.Transport.Network_Name.ZmqLMCPNetwork,
         Socket_Address          => Socket_Address,
         Is_Receive              => False,
         Zmq_Socket_Type         => Zmq_SocketType,
         Number_of_IO_Threads    => 1,
         Is_Server_Bind          => Is_Server,
         Receive_High_Water_Mark => Zmq_High_Water_Mark,
         Send_High_Water_Mark    => Zmq_High_Water_Mark);

      --  m_transportSender = UxAS::stdUxAS::make_unique<UxAS::communications::transport::ZeroMqAddressedAttributedMessageSender>(
      --          (zmqSocketType == ZMQ_STREAM ? true : false));
      This.Sender := new ZeroMq_Addressed_Attributed_Message_Sender (Zmq_SocketType);
      --  we just pass the actual socket type and let the sender do the test

      --  m_transportSender->initialize(sourceGroup, m_entityId, m_serviceId, zmqLMCPNetworkSendSocket);
      This.Sender.Initialize
        (Source_Group => Source_Group,
         Entity_Id    => Entity_Id,
         Service_Id   => Service_Id,
         SocketConfig => zmqLMCPNetworkSendSocket);
   end Initialize_Zmq_Socket;

end UxAS.Comms.LMCP_Object_Message_Sender_Pipes;
