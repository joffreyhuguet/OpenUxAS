with Ada.Text_IO; use Ada.Text_IO;
with Plan_Builder_Communication; use Plan_Builder_Communication;
with UxAS.Messages.lmcptask.TaskAssignmentSummary; use UxAS.Messages.lmcptask.TaskAssignmentSummary;
with UxAS.Messages.lmcptask.TaskImplementationResponse; use UxAS.Messages.lmcptask.TaskImplementationResponse;
with UxAS.Messages.lmcptask.TaskImplementationRequest; use UxAS.Messages.lmcptask.TaskImplementationRequest;
with UxAS.Messages.lmcptask.PlanningState; use UxAS.Messages.lmcptask.PlanningState;
with AFRL.CMASI.LoiterAction; use AFRL.CMASI.LoiterAction;
with LMCP_Message_Conversions; use LMCP_Message_Conversions;
with Ada.Numerics.Generic_Elementary_Functions;
with Unit_Conversion_Utilities;
with Ada.Containers.Vectors;
with Common; use Common;
with AVTAS.LMCP.Types;
with LMCP_Messages; use LMCP_Messages;
with AFRL.CMASI.Enumerations; use AFRL.CMASI.Enumerations;
with Ada.Strings.Unbounded; use  Ada.Strings.Unbounded;
with UxAS.Messages.lmcptask.TaskAssignment;
with AFRL.CMASI.Waypoint;
with AVTAS.LMCP.Object;

package body Plan_Builder with SPARK_Mode is
   pragma Unevaluated_Use_Of_Old (Allow);

   pragma Assertion_Policy (Ignore);

   --  Subprograms wraping insertion and deletion in m_pendingRoute. They
   --  restate part of the postcondition of the callee, but also reestablish
   --  the predicate of Route_Aggregator_State and compute the effect of the
   --  modification on Plan_To_Route.

   -----------------------
   -- Local subprograms --
   -----------------------
   package My_Conversions is new Unit_Conversion_Utilities (Real64);
   use My_Conversions;

   package Functions is new Ada.Numerics.Generic_Elementary_Functions (Real64);
   use Functions;

   -------------------------------------
   -- Process_Task_Assignment_Summary --
   -------------------------------------
   procedure Process_Task_Assignment_Summary
     (State            : in out Plan_Builder_State;
      Config           : in out Plan_Builder_Configuration_Data;
      Mailbox          : in out Plan_Builder_Mailbox;
      Received_Message : not null TaskAssignmentSummary_Any;
      Should_Terminate : out Boolean)
   is
      ReqId : Int64 := Int64 (Received_Message.getCorrespondingAutomationRequestID);
      AReq : UniqueAutomationRequest;
      AResp : UniqueAutomationResponse;
      Planning_State : LMCP_Messages.PlanningState;
      North_M : Real64 := 0.0;
      East_M : Real64 := 0.0;
      Latitude_Deg : Real64 := 0.0;
      Longitude_Deg : Real64 := 0.0;
   begin

      if Contains (State.m_uniqueAutomationRequests, ReqId) then
         AReq := Element (State.m_uniqueAutomationRequests, ReqId);
      else
         declare
            Message : Ada.Strings.Unbounded.Unbounded_String := To_Unbounded_String ("ERROR::processTaskAssignmentSummary: Corresponding Unique Automation Request ID [" & ReqId'Image & "] not found!");
         begin
            sendErrorMessage (Mailbox, Message);
         end;
         return;
      end if;

      if Received_Message.getTaskList.all.Is_Empty then
         declare
            Message : Ada.Strings.Unbounded.Unbounded_String := To_Unbounded_String ("No assignments found for request " & ReqId'Image);
         begin
            sendErrorMessage (Mailbox, Message);
         end;
         return;
      end if;

      for VehicleId of AReq.EntityList loop
         if not Has_Key (State.m_currentEntityStates, VehicleId) then
            declare
               Message : Ada.Strings.Unbounded.Unbounded_String := To_Unbounded_String ("ERROR::processTaskAssignmentSummary: Corresponding Unique Automation Request included vehicle ID [" & VehicleId'Image & "] which does not have a corresponding current state!");
            begin
               sendErrorMessage (Mailbox, Message);
            end;
            return;
         end if;
      end loop;

    -- initialize state tracking maps with this corresponding request IDs
    -- m_assignmentSummaries[taskAssignmentSummary->getCorrespondingAutomationRequestID()] = taskAssignmentSummary;
      Insert (State.m_assignmentSummaries, ReqId, As_TaskAssignmentSummary_Message (Received_Message));

      declare
         ProjectedState : ProjectedState_Seq;
      begin
         -- m_projectedEntityStates[taskAssignmentSummary->getCorrespondingAutomationRequestID()] = std::vector< std::shared_ptr<ProjectedState> >();
         State.m_projectedEntityStates := Int64_PS_Maps.Add (State.m_projectedEntityStates, ReqId, ProjectedState);
      end;

      declare
         UniqueAutReq_List : TaskAssignment_Ref_Deque;
      begin
         -- m_remainingAssignments[taskAssignmentSummary->getCorrespondingAutomationRequestID()] = std::deque< std::shared_ptr<uxas::messages::task::TaskAssignment> >();
         Insert (State.m_remainingAssignments, ReqId, UniqueAutReq_List);
      end;

    -- m_inProgressResponse[taskAssignmentSummary->getCorrespondingAutomationRequestID()] = std::make_shared<uxas::messages::task::UniqueAutomationResponse>();
    -- m_inProgressResponse[taskAssignmentSummary->getCorrespondingAutomationRequestID()]->setResponseID(taskAssignmentSummary->getCorrespondingAutomationRequestID());

      AResp.ResponseID := ReqId;
      Insert (State.m_inProgressResponse, ReqId, AResp);

      if Length (AReq.EntityList) = 0 then
         for S of State.m_currentEntityStates loop
            AReq.EntityList := Add (AReq.EntityList, S);
         end loop;
      end if;

      for VehicleID of AReq.EntityList loop
         declare
            Entity_State : LMCP_Messages.EntityState := ES_Maps.Get (State.m_currentEntityStates, VehicleID);
            Projected_State : ProjectedState;
            Found_State : Boolean := False;
            Converter : Unit_Converter;
         begin
            Projected_State.FinalWaypointID := 0;
            Projected_State.Time := Entity_State.Time;
            for P_State of AReq.PlanningStates loop
               if P_State.EntityID = VehicleID then
                  Found_State := True;
                  Projected_State.State := P_State;
                  exit;
               end if;
               if not Found_State then
                  Planning_State.EntityID := VehicleID;
                  Planning_State.PlanningPosition := Entity_State.Location;
                  Planning_State.PlanningHeading := Entity_State.Heading;
                  Convert_LatLong_Degrees_To_NorthEast_Meters (Converter, Entity_State.Location.Latitude, Entity_State.Location.Longitude, North_M, East_M);
                  North_M := North_M + Config.m_assignmentStartPointLead_m * (Cos (Real64 (Entity_State.Heading)) * dDegreesToRadians);
                  East_M := East_M + Config.m_assignmentStartPointLead_m * (Sin (Real64 (Entity_State.Heading)) * dDegreesToRadians);
                  Convert_NorthEast_Meters_To_LatLong_Degrees (Converter, North_M, East_M, Latitude_Deg, Longitude_Deg);
                  Planning_State.PlanningPosition.Latitude := Latitude_Deg;
                  Planning_State.PlanningPosition.Longitude := Longitude_Deg;
                  Projected_State.State := Planning_State;
               end if;
               declare
                  Proj : ProjectedState_Seq := Int64_PS_Maps.Get (State.m_projectedEntityStates, ReqId);
               begin
                  Proj := Add (Proj, Projected_State);
               end;
            end loop;
         end;
      end loop;

      for T of Received_Message.getTaskList.all loop
         declare
            use UxAS.Messages.lmcptask.TaskAssignment;
            Assign : TaskAssignment_Ref_Deque := Element (State.m_remainingAssignments, ReqId);
            Task_Assignment : LMCP_Messages.TaskAssignment := As_TaskAssignment_Message (T);
         begin
            Append (Assign, Task_Assignment);
         end;
      end loop;
      Send_Next_Task_Implementation_Request (ReqId, Mailbox, State, Config);
   end Process_Task_Assignment_Summary;

   procedure Send_Next_Task_Implementation_Request
     (uniqueRequestID : Int64;
      Mailbox          : in out Plan_Builder_Mailbox;
      State : in out Plan_Builder_State;
      Config : in out Plan_Builder_Configuration_Data)
   is
   begin
    --  if(m_uniqueAutomationRequests.find(uniqueRequestID) == m_uniqueAutomationRequests.end())
    --      return false;
      if Contains (State.m_uniqueAutomationRequests, uniqueRequestID) then
    --  if(m_remainingAssignments[uniqueRequestID].empty())
    --      return false;
         if Is_Empty (Element (State.m_remainingAssignments, uniqueRequestID)) then
            return;
         end if;

         declare
            --  auto taskAssignment = m_remainingAssignments[uniqueRequestID].front();
            taskAssignment : LMCP_Messages.TaskAssignment := First_Element (Element (State.m_remainingAssignments, uniqueRequestID));
            --  auto taskImplementationRequest = std::make_shared<uxas::messages::task::TaskImplementationRequest>();
            taskImplementationRequest : TaskImplementationRequest_Acc := new UxAS.Messages.lmcptask.TaskImplementationRequest.TaskImplementationRequest;
            -- TODO
    --  auto planState = std::find_if(m_projectedEntityStates[uniqueRequestID].begin(), m_projectedEntityStates[uniqueRequestID].end(),
    --                                [&](std::shared_ptr<ProjectedState> state)
    --                                { return( (!state || !(state->state)) ? false : (state->state->getEntityID() == taskAssignment->getAssignedVehicle()) ); });
            planState : ProjectedState;
         begin
            --  if(planState == m_projectedEntityStates[uniqueRequestID].end())
            --      return false;
            --  if(!( (*planState)->state ) )
            --      return false;

            --  taskImplementationRequest->setCorrespondingAutomationRequestID(uniqueRequestID);
            taskImplementationRequest.setCorrespondingAutomationRequestID (AVTAS.LMCP.Types.Int64 (uniqueRequestID));
            --  m_expectedResponseID[m_taskImplementationId] = uniqueRequestID;
            --  taskImplementationRequest->setRequestID(m_taskImplementationId++);
            taskImplementationRequest.setRequestID (AVTAS.LMCP.Types.Int64 (Config.m_taskImplementationId));
            Config.m_taskImplementationId := Config.m_taskImplementationId + 1;
            --  taskImplementationRequest->setStartingWaypointID( (*planState)->finalWaypointID + 1 );
            taskImplementationRequest.setStartingWaypointID (AVTAS.LMCP.Types.Int64 (planState.FinalWaypointID + 1));
            --  taskImplementationRequest->setVehicleID(taskAssignment->getAssignedVehicle());
            taskImplementationRequest.setVehicleID (AVTAS.LMCP.Types.Int64 (taskAssignment.AssignedVehicle));
            --  taskImplementationRequest->setTaskID(taskAssignment->getTaskID());
            taskImplementationRequest.setTaskID (AVTAS.LMCP.Types.Int64 (taskAssignment.TaskID));
            --  taskImplementationRequest->setOptionID(taskAssignment->getOptionID());
            taskImplementationRequest.setOptionID (AVTAS.LMCP.Types.Int64 (taskAssignment.OptionID));
            --  taskImplementationRequest->setRegionID(m_uniqueAutomationRequests[uniqueRequestID]->getOriginalRequest()->getOperatingRegion());
            taskImplementationRequest.setRegionID (AVTAS.LMCP.Types.Int64 (Element (State.m_uniqueAutomationRequests, uniqueRequestID).OperatingRegion));
            --  taskImplementationRequest->setTimeThreshold(taskAssignment->getTimeThreshold());
            taskImplementationRequest.setTimeThreshold (AVTAS.LMCP.Types.Int64 (taskAssignment.TimeThreshold));
            --  taskImplementationRequest->setStartHeading((*planState)->state->getPlanningHeading());
            taskImplementationRequest.setStartHeading (AVTAS.LMCP.Types.Real32 (planState.State.PlanningHeading));
            --  taskImplementationRequest->setStartPosition((*planState)->state->getPlanningPosition()->clone());
            taskImplementationRequest.setStartPosition (As_Location3D_Any (planState.State.PlanningPosition));
            --  taskImplementationRequest->setStartTime((*planState)->time);
            taskImplementationRequest.setStartTime (AVTAS.LMCP.Types.Int64 (planState.Time));
            --  for(auto neighbor : m_projectedEntityStates[uniqueRequestID])
            --  {
            for neighbor of Int64_PS_Maps.Get (State.m_projectedEntityStates, uniqueRequestID) loop
               --      if(neighbor && neighbor->state && neighbor->state->getEntityID() != (*planState)->state->getEntityID())
               --      {
               --          taskImplementationRequest->getNeighborLocations().push_back(neighbor->state->clone());
               declare
                  NeighborLocation : PlanningState_Acc := new UxAS.Messages.lmcptask.PlanningState.PlanningState;
               begin
                  NeighborLocation.setEntityID (AVTAS.LMCP.Types.Int64 (neighbor.State.EntityID));
                  NeighborLocation.setPlanningPosition (As_Location3D_Any (neighbor.State.PlanningPosition));
                  NeighborLocation.setPlanningHeading (AVTAS.LMCP.Types.Real32 (neighbor.State.PlanningHeading));
                  taskImplementationRequest.getNeighborLocations.all.Append (NeighborLocation);
               end;
               --      }
               --  }
            end loop;

            --  m_remainingAssignments[uniqueRequestID].pop_front();
            declare
               Remaining_Assignmens : TaskAssignment_Ref_Deque := Element (State.m_remainingAssignments, uniqueRequestID);
            begin
               Delete_First (Remaining_Assignmens);
            end;

            --  sendSharedLmcpObjectBroadcastMessage(taskImplementationRequest);
            sendBroadcastMessage_Any (Mailbox, AVTAS.LMCP.Object.Object_Any (taskImplementationRequest));
         end;
      end if;
   end Send_Next_Task_Implementation_Request;

   procedure Process_Task_Implementation_Response
     (State            : in out Plan_Builder_State;
      Config           : in out Plan_Builder_Configuration_Data;
      Mailbox          : in out Plan_Builder_Mailbox;
      Received_Message : not null TaskImplementationResponse_Any)
   is
      uniqueRequestID : Int64;
      Resp_ID : Int64 := Int64 (Received_Message.getResponseID);
      Vehicle_ID : Int64 := Int64 (Received_Message.getVehicleID);
      corrMish : MissionCommand;
      use AVTAS.LMCP.Types;
   begin

      if Contains (State.m_expectedResponseID, Resp_ID) then
         uniqueRequestID := Element (State.m_expectedResponseID, Resp_ID);
         if (not Contains (State.m_inProgressResponse, uniqueRequestID)) or (not Contains (State.m_inProgressResponse, uniqueRequestID)) or (Length (Element (State.m_inProgressResponse, uniqueRequestID).MissionCommandList) = 0) then
            return;
         end if;

         if Received_Message.getTaskWaypoints.all.Is_Empty then
            declare
               Error_Msg : String := "";
            begin
               Error_Msg := "Task [" & Received_Message.getTaskID'Image & "]";
               Error_Msg := Error_Msg & " option [" & Received_Message.getOptionID'Image & "]";
               Error_Msg := Error_Msg & " assigned to vehicle [" & Received_Message.getVehicleID'Image & "]";
               Error_Msg := Error_Msg & " reported an empty waypoint list for implementation!";
               sendErrorMessage (Mailbox, To_Unbounded_String (Error_Msg));

               Check_Next_Task_Implementation_Request (uniqueRequestID, Mailbox, State, Config);
               return;
            end;
         end if;
             --  auto corrMish = std::find_if(m_inProgressResponse[uniqueRequestID]->getOriginalResponse()->getMissionCommandList().begin(), m_inProgressResponse[uniqueRequestID]->getOriginalResponse()->getMissionCommandList().end(),
             --                     [&](afrl::cmasi::MissionCommand* mish) { return mish->getVehicleID() == taskImplementationResponse->getVehicleID(); });
         declare
            MissionCo_List : MissionCommand_Seq := Element (State.m_inProgressResponse, uniqueRequestID).MissionCommandList;
            Found : Boolean := False;
         begin
            for MC of MissionCo_List loop
               if MC.VehicleId = Vehicle_ID then
                  corrMish := MC;
                  Found := True;
               end if;
            end loop;

            if Found then
               if Length (corrMish.WaypointList) /= 0 then
                  declare
                     use AFRL.CMASI.Waypoint;
                     WP : LMCP_Messages.Waypoint :=  Get (corrMish.WaypointList, Last (corrMish.WaypointList));
                     Task_WPs : Waypoint_Any := Received_Message.getTaskWaypoints.all.First_Element;
                  begin
                     WP.NextWaypoint := Common.Int64 (Task_WPs.getNumber);
                  end;
               end if;
               for WayPoint of Received_Message.getTaskWaypoints.all loop
                  corrMish.WaypointList := Add (corrMish.WaypointList, As_Waypoint_Message (WayPoint));
               end loop;

            else

               for ReqID of State.m_reqeustIDVsOverrides loop
                  for Speed_Alt_Pair of Element (State.m_reqeustIDVsOverrides, ReqID) loop
                     if ((Speed_Alt_Pair.getVehicleID = AVTAS.LMCP.Types.Int64 (Vehicle_ID)) and (Speed_Alt_Pair.getTaskID = Received_Message.getTaskID)) or (Speed_Alt_Pair.getTaskID = 0) then
                        for Way_Point of Received_Message.getTaskWaypoints.all loop
                           Way_Point.setAltitude (Speed_Alt_Pair.getAltitude);
                           Way_Point.setSpeed (Speed_Alt_Pair.getSpeed);
                           Way_Point.setAltitudeType (Speed_Alt_Pair.getAltitudeType);

                           for Action of Way_Point.getVehicleActionList.all loop
                              if Action.all in LoiterAction'Class then
                                 LoiterAction_Any (Action).getLocation.setAltitude (Speed_Alt_Pair.getAltitude);
                              end if;
                           end loop;

                        end loop;
                     end if;
                  end loop;
               end loop;
            end if;
         end;

      end if;

   end Process_Task_Implementation_Response;

   procedure Check_Next_Task_Implementation_Request
     (uniqueRequestID : Int64;
      Mailbox : in out Plan_Builder_Mailbox;
      State : in out Plan_Builder_State;
      Config : in out Plan_Builder_Configuration_Data)
   is
      Response : UniqueAutomationResponse := Element (State.m_inProgressResponse, uniqueRequestID);
      Service_Status : ServiceStatus;
      Key_Value_Pair : KeyValuePair;
   begin
      if Contains (State.m_remainingAssignments, uniqueRequestID) then
         if Is_Empty (Element (State.m_remainingAssignments, uniqueRequestID)) then
            if Has_Key (State.m_projectedEntityStates, uniqueRequestID) then
               for E of Int64_PS_Maps.Get (State.m_projectedEntityStates, uniqueRequestID) loop
                  -- TODO        if(e && e->state)
                  declare
                     UnAResp : UniqueAutomationResponse := Element (State.m_inProgressResponse, uniqueRequestID);
                  begin
                     UnAResp.FinalStates := Add (UnAResp.FinalStates, E.State);
                  end;
                  -- end if;
               end loop;
            end if;

            if Config.m_addLoiterToEndOfMission then
               Add_Loiters_To_Mission_Commands (State, Config, Mailbox, Response);
            end if;

            if Config.m_overrideTurnType then
               for Mission of Response.MissionCommandList loop
                  for I in Mission.WaypointList loop
                     declare
                        WP : LMCP_Messages.Waypoint := Get (Mission.WaypointList, I);
                     begin
                        WP.TurnType := Config.m_turnType;
                     end;
                  end loop;

               end loop;
            end if;

            sendBroadcastMessage (Mailbox, Response);

            Delete (State.m_inProgressResponse, uniqueRequestID);
            Delete (State.m_reqeustIDVsOverrides, uniqueRequestID);

            Service_Status.StatusType := Information;

            declare
               Message : Unbounded_String := To_Unbounded_String ("UniqueAutomationResponse[" & uniqueRequestID'Image & "] - sent");
            begin
               Key_Value_Pair.Key := Message;
               Service_Status.Info := Add (Service_Status.Info, Key_Value_Pair);
               sendBroadcastMessage (Mailbox, Key_Value_Pair);
            end;
         else
            Send_Next_Task_Implementation_Request (uniqueRequestID, Mailbox, State, Config);
         end if;

      end if;

   end Check_Next_Task_Implementation_Request;

   -------------------------------------
   -- Add_Loiters_To_Mission_Commands --
   -------------------------------------

   procedure Add_Loiters_To_Mission_Commands
     (State : in out Plan_Builder_State;
      Config : in out Plan_Builder_Configuration_Data;
      Mailbox : in out Plan_Builder_Mailbox;
      Response : UniqueAutomationResponse)
   is
      Contains_Loiter : Boolean := False;
      Target_Vehicle : Int64;
   begin

      for Mission of Response.MissionCommandList loop

         for Way_Point of Mission.WaypointList loop
            for Action of Way_Point.VehicleActionList loop
               if Action.LoiterAction then
                  Contains_Loiter := True;
               end if;
            end loop;
         end loop;
      end loop;

      if Contains_Loiter then
         return;
      end if;

      for Mission of Response.MissionCommandList loop
         if Mission.VehicleId /= Target_Vehicle then
            --      IMPACT_INFORM("Automation Response contains mission commands for multiple vehicles. No loiters!!");
            return;
         end if;
      end loop;

      if Has_Key (State.m_currentEntityStates, Target_Vehicle) then
         declare
            Entity_State : EntityState := ES_Maps.Get (State.m_currentEntityStates, Target_Vehicle);
            Wp_List : WP_Seq := Get (Response.MissionCommandList, Last (Response.MissionCommandList)).WaypointList;
            Back_El : LMCP_Messages.Waypoint := Get (Wp_List, Last (Wp_List));
            Loiter_Action : VehicleAction;
         begin
            if Entity_State.isGroundVehicleState or Entity_State.isSurfaceVehicleState then
               Loiter_Action.LoiterType :=  Hover;
            else
               Loiter_Action.LoiterType :=  Circular;
               Loiter_Action.Radius := Config.m_deafultLoiterRadius;
            end if;
            Loiter_Action.Location := (Back_El.Latitude, Back_El.Longitude, Back_El.Altitude, Back_El.AltitudeType);
            --  Loiter_Action-Airspeed := Back_El.GroundSpeed; TODO
            Back_El.VehicleActionList := Add (Back_El.VehicleActionList, Loiter_Action);
         end;
      end if;
   end Add_Loiters_To_Mission_Commands;

end Plan_Builder;
