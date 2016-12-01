/*
 * tuning.xc
 *
 *  Created on: Jul 13, 2015
 *      Author: Synapticon GmbH
 */
#include <tuning.h>
#include <stdio.h>
#include <ctype.h>
#include <state_modes.h>

#if 0
static void brake_shake(interface MotorcontrolInterface client i_motorcontrol, int torque) {
    const int period = 50;
    i_motorcontrol.set_brake_status(1);
    for (int i=0 ; i<1 ; i++) {
        i_motorcontrol.set_torque(torque);
        delay_milliseconds(period);
        i_motorcontrol.set_torque(-torque);
        delay_milliseconds(period);
    }
    i_motorcontrol.set_torque(0);
}
#endif

/*
 * Function to call while in tuning opmode
 *
 * Assumption: this function is called every 1ms! (like the standard control does)
 *
 * FIXME
 * - get rid of {Upsream,Downstream}ControlData here, the data exchange should exclusively happen
 *   in the calling ethercat_drive_service.
 */
int tuning_handler_ethercat(
        /* input */  uint16_t    controlword, uint32_t control_extension,
        /* output */ uint16_t    &statusword, uint32_t &tuning_result,
        TuningStatus             &tuning_status,
        MotorcontrolConfig       &motorcontrol_config,
        PosVelocityControlConfig &pos_velocity_ctrl_config,
        PositionFeedbackConfig   &pos_feedback_config,
        UpstreamControlData      &upstream_control_data,
        DownstreamControlData    &downstream_control_data,
        client interface PositionVelocityCtrlInterface i_position_control,
        client interface PositionFeedbackInterface ?i_position_feedback
    )
{
    //FIXME get rid of static variables
    static uint8_t status_mux     = 0;
    static uint8_t status_display = 0;

    //mux send offsets and other data in the user4 pdo using the lower bits of statusword
    status_mux = ((status_mux + 1) >= 18) ? 0 : status_mux + 1;
    switch(status_mux) {
    case 0: //send flags
        //convert polarity flag to 0/1
        int motion_polarity = 0;
        if (pos_velocity_ctrl_config.polarity == INVERTED_POLARITY) {
            motion_polarity = 1;
        }
        int sensor_polarity = 0;
        if (pos_feedback_config.polarity == INVERTED_POLARITY) {
            sensor_polarity = 1;
        }
        int  brake_release_strategy = 0;
        if (pos_velocity_ctrl_config.special_brake_release == 1) {
            brake_release_strategy = 1;
        }
        tuning_result = (tuning_status.motorctrl_status<<3)+(sensor_polarity<<2)+(motion_polarity<<1)+tuning_status.brake_flag;
        break;
    case 1: //send offset
        tuning_result = motorcontrol_config.commutation_angle_offset;
        break;
    case 2: //pole pairs
        tuning_result = motorcontrol_config.pole_pair;
        break;
    case 3: //target
        switch(tuning_status.motorctrl_status) {
        case TUNING_MOTORCTRL_TORQUE:
            tuning_result = downstream_control_data.torque_cmd;
            break;
        case TUNING_MOTORCTRL_VELOCITY:
            tuning_result = downstream_control_data.velocity_cmd;
            break;
        case TUNING_MOTORCTRL_POSITION:
        case TUNING_MOTORCTRL_POSITION_PROFILER:
            tuning_result = downstream_control_data.position_cmd;
            break;
        }
        break;
    case 4: //position limit min
        tuning_result = pos_velocity_ctrl_config.min_pos;
        break;
    case 5: //position limit max
        tuning_result = pos_velocity_ctrl_config.max_pos;
        break;
    case 6: //max speed
        tuning_result = pos_velocity_ctrl_config.max_speed;
        break;
    case 7: //max torque
        tuning_result = pos_velocity_ctrl_config.max_torque;
        break;
    case 8: //P_pos
        tuning_result = pos_velocity_ctrl_config.P_pos;
        break;
    case 9: //I_pos
        tuning_result = pos_velocity_ctrl_config.I_pos;
        break;
    case 10: //D_pos
        tuning_result = pos_velocity_ctrl_config.D_pos;
        break;
    case 11: //integral_limit_pos
        tuning_result = pos_velocity_ctrl_config.integral_limit_pos;
        break;
    case 12: //
        tuning_result = pos_velocity_ctrl_config.P_velocity;
        break;
    case 13: //
        tuning_result = pos_velocity_ctrl_config.I_velocity;
        break;
    case 14: //
        tuning_result = pos_velocity_ctrl_config.D_velocity;
        break;
    case 15: //
        tuning_result = pos_velocity_ctrl_config.integral_limit_velocity;
        break;
    case 16: //fault code
        tuning_result = upstream_control_data.error_status;
        break;
    default: //special_brake_release
        tuning_result = pos_velocity_ctrl_config.special_brake_release;
        break;
    }

    if ((controlword & 0xff) == 'p') { //cyclic position mode
        downstream_control_data.position_cmd = tuning_status.value;

    } else {//command mode
        tuning_status.mode_1 = 0; //default command do nothing

        //check for new command
        if (controlword == 0) { //no mode
            status_display = 0; //reset status display
        } else if (status_display != (controlword & 0xff)) {//it's a new command
            status_display = (controlword & 0xff); //set controlword display to the master
            tuning_status.value    = tuning_status.value;
            tuning_status.mode_1   = controlword         & 0xff;
            tuning_status.mode_2   = (controlword >>  8) & 0xff;
            tuning_status.mode_3   = control_extension   & 0xff;
        }

        /* print command */
        if (tuning_status.mode_1 >=32 && tuning_status.mode_1 <= 126) { //mode is a printable ascii char
            if (tuning_status.mode_2 != 0) {
                if (tuning_status.mode_3 != 0) {
                    printf("%c %c %c %d\n", tuning_status.mode_1, tuning_status.mode_2, tuning_status.mode_3, tuning_status.value);
                } else {
                    printf("%c %c %d\n", tuning_status.mode_1, tuning_status.mode_2, tuning_status.value);
                }
            } else {
                printf("%c %d\n", tuning_status.mode_1, tuning_status.value);
            }
        }

        //execute command
        tuning_command(tuning_status,
                motorcontrol_config, pos_velocity_ctrl_config, pos_feedback_config,
                upstream_control_data, downstream_control_data,
                i_position_control, i_position_feedback);
    }

    //put status display and status mux in statusword
    statusword = ((status_display & 0xff) << 8) | (status_mux & 0xff);

    return 0;
}



void tuning_command(
        TuningStatus             &tuning_status,
        MotorcontrolConfig       &motorcontrol_config,
        PosVelocityControlConfig &pos_velocity_ctrl_config,
        PositionFeedbackConfig   &pos_feedback_config,
        UpstreamControlData      &upstream_control_data,
        DownstreamControlData    &downstream_control_data,
        client interface PositionVelocityCtrlInterface i_position_control,
        client interface PositionFeedbackInterface ?i_position_feedback
    )
{

    //repeat
    const int tolerance = 1000;
    if (tuning_status.repeat_flag == 1) {
        if (upstream_control_data.position < (downstream_control_data.position_cmd+tolerance) &&
            upstream_control_data.position > (downstream_control_data.position_cmd-tolerance)) {
            downstream_control_data.position_cmd = -downstream_control_data.position_cmd;
        }
    }

    /* execute command */
    switch(tuning_status.mode_1) {
    //position commands
    case 'p':
        downstream_control_data.offset_torque = 0;
        downstream_control_data.position_cmd = tuning_status.value;
        pos_velocity_ctrl_config = i_position_control.get_position_velocity_control_config();
        switch(tuning_status.mode_2)
        {
        //direct command with profile
        case 'p':
                //bug: the first time after one p# command p0 doesn't use the profile; only the way back to zero
                pos_velocity_ctrl_config.enable_profiler = 1;
                i_position_control.set_position_velocity_control_config(pos_velocity_ctrl_config);
                printf("Go to %d with profile\n", tuning_status.value);
                upstream_control_data = i_position_control.update_control_data(downstream_control_data);
                break;
        //step command (forward and backward)
        case 's':
                switch(tuning_status.mode_3)
                {
                //with profile
                case 'p':
                        pos_velocity_ctrl_config.enable_profiler = 1;
                        printf("position cmd: %d to %d with profile\n", tuning_status.value, -tuning_status.value);
                        break;
                //without profile
                default:
                        pos_velocity_ctrl_config.enable_profiler = 0;
                        printf("position cmd: %d to %d\n", tuning_status.value, -tuning_status.value);
                        break;
                }
                i_position_control.set_position_velocity_control_config(pos_velocity_ctrl_config);
                downstream_control_data.offset_torque = 0;
                downstream_control_data.position_cmd = tuning_status.value;
                upstream_control_data = i_position_control.update_control_data(downstream_control_data);
                delay_milliseconds(1500);
                downstream_control_data.position_cmd = -tuning_status.value;
                upstream_control_data = i_position_control.update_control_data(downstream_control_data);
                delay_milliseconds(1500);
                downstream_control_data.position_cmd = 0;
                upstream_control_data = i_position_control.update_control_data(downstream_control_data);
                break;
        //direct command
        default:
                pos_velocity_ctrl_config.enable_profiler = 0;
                i_position_control.set_position_velocity_control_config(pos_velocity_ctrl_config);
                printf("Go to %d\n", tuning_status.value);
                upstream_control_data = i_position_control.update_control_data(downstream_control_data);
                break;
        }
        break;

    //repeat
    case 'R':
        if (tuning_status.value) {
            downstream_control_data.position_cmd = upstream_control_data.position+tuning_status.value;
            tuning_status.repeat_flag = 1;
        } else {
            tuning_status.repeat_flag = 0;
        }
        break;

    //set velocity
    case 'v':
        downstream_control_data.velocity_cmd = tuning_status.value;
        upstream_control_data = i_position_control.update_control_data(downstream_control_data);
        printf("set velocity %d\n", downstream_control_data.velocity_cmd);
        break;

    //change pid coefficients
    case 'k':
        pos_velocity_ctrl_config = i_position_control.get_position_velocity_control_config();
        switch(tuning_status.mode_2) {
        case 'p': //position
            switch(tuning_status.mode_3) {
            case 'p':
                pos_velocity_ctrl_config.P_pos = tuning_status.value;
                break;
            case 'i':
                pos_velocity_ctrl_config.I_pos = tuning_status.value;
                break;
            case 'd':
                pos_velocity_ctrl_config.D_pos = tuning_status.value;
                break;
            case 'l':
                pos_velocity_ctrl_config.integral_limit_pos = tuning_status.value;
                break;
            case 'j':
                pos_velocity_ctrl_config.j = tuning_status.value;
                break;
            default:
                printf("Pp:%d Pi:%d Pd:%d Pi lim:%d j:%d\n", pos_velocity_ctrl_config.P_pos, pos_velocity_ctrl_config.I_pos, pos_velocity_ctrl_config.D_pos,
                        pos_velocity_ctrl_config.integral_limit_pos, pos_velocity_ctrl_config.j);
                break;
            }
            break;
            case 'v': //velocity
                switch(tuning_status.mode_3) {
                case 'p':
                    pos_velocity_ctrl_config.P_velocity = tuning_status.value;
                    break;
                case 'i':
                    pos_velocity_ctrl_config.I_velocity = tuning_status.value;
                    break;
                case 'd':
                    pos_velocity_ctrl_config.D_velocity = tuning_status.value;
                    break;
                case 'l':
                    pos_velocity_ctrl_config.integral_limit_velocity = tuning_status.value;
                    break;
                default:
                    printf("Kp:%d Ki:%d Kd:%d\n", pos_velocity_ctrl_config.P_velocity, pos_velocity_ctrl_config.I_velocity, pos_velocity_ctrl_config.D_velocity);
                    break;
                }
                break;
        } /* end mode_2 */
        i_position_control.set_position_velocity_control_config(pos_velocity_ctrl_config);
        break;

    //limits
    case 'L':
        pos_velocity_ctrl_config = i_position_control.get_position_velocity_control_config();
        switch(tuning_status.mode_2) {
            //max torque
            case 't':
                pos_velocity_ctrl_config.max_torque = tuning_status.value;
                motorcontrol_config.max_torque = tuning_status.value;
                i_position_control.set_motorcontrol_config(motorcontrol_config);
                tuning_status.brake_flag = 0;
                tuning_status.motorctrl_status = TUNING_MOTORCTRL_OFF;
                break;
            //max speed
            case 's':
            case 'v':
                pos_velocity_ctrl_config.max_speed = tuning_status.value;
                break;
            //max position
            case 'p':
                switch(tuning_status.mode_3) {
                case 'u':
                    pos_velocity_ctrl_config.max_pos = tuning_status.value;
                    break;
                case 'l':
                    pos_velocity_ctrl_config.min_pos = tuning_status.value;
                    break;
                default:
                    pos_velocity_ctrl_config.max_pos = tuning_status.value;
                    pos_velocity_ctrl_config.min_pos = -tuning_status.value;
                    break;
                }
                break;
        } /* end mode_2 */
        i_position_control.set_position_velocity_control_config(pos_velocity_ctrl_config);
        break;

    //enable position control
    case 'e':
        if (tuning_status.value > 0) {
            tuning_status.brake_flag = 1;
            switch(tuning_status.mode_2) {
            case 'p':
                tuning_status.motorctrl_status = TUNING_MOTORCTRL_POSITION;
                upstream_control_data = i_position_control.update_control_data(downstream_control_data);
                downstream_control_data.position_cmd = upstream_control_data.position;
                upstream_control_data = i_position_control.update_control_data(downstream_control_data);
                printf("start position %d\n", downstream_control_data.position_cmd);

                //select profiler
                pos_velocity_ctrl_config = i_position_control.get_position_velocity_control_config();
                if (tuning_status.mode_3 == 'p') {
                    pos_velocity_ctrl_config.enable_profiler = 1;
                    tuning_status.motorctrl_status = TUNING_MOTORCTRL_POSITION_PROFILER;
                } else {
                    pos_velocity_ctrl_config.enable_profiler = 0;
                }
                i_position_control.set_position_velocity_control_config(pos_velocity_ctrl_config);

                //select control mode
                switch(tuning_status.value) {
                case 1:
                    i_position_control.enable_position_ctrl(POS_PID_CONTROLLER);
                    printf("simpe PID pos ctrl enabled\n");
                    break;
                case 2:
                    i_position_control.enable_position_ctrl(POS_PID_VELOCITY_CASCADED_CONTROLLER);
                    printf("vel.-cascaded pos ctrl enabled\n");
                    break;
                case 3:
                    i_position_control.enable_position_ctrl(NL_POSITION_CONTROLLER);
                    printf("Nonlinear pos ctrl enabled\n");
                    break;
                default:
                    i_position_control.enable_position_ctrl(pos_velocity_ctrl_config.control_mode);
                    printf("%d pos ctrl enabled\n", pos_velocity_ctrl_config.control_mode);
                    break;
                }
                break;
            case 'v':
                tuning_status.motorctrl_status = TUNING_MOTORCTRL_VELOCITY;
                downstream_control_data.velocity_cmd = 0;
                i_position_control.enable_velocity_ctrl();
                printf("velocity ctrl enabled\n");
                break;
            case 't':
                tuning_status.motorctrl_status = TUNING_MOTORCTRL_TORQUE;
                downstream_control_data.torque_cmd = 0;
                i_position_control.enable_torque_ctrl();
                printf("torque ctrl enabled\n");
                break;
            }
        } else {
            tuning_status.brake_flag = 0;
            tuning_status.repeat_flag = 0;
            tuning_status.motorctrl_status = TUNING_MOTORCTRL_OFF;
            i_position_control.disable();
            printf("position ctrl disabled\n");
        }
        break;

    //pole pairs
    case 'P':
        if (!isnull(i_position_feedback)) {
            motorcontrol_config.pole_pair = tuning_status.value;
            pos_feedback_config.pole_pairs = tuning_status.value;
            tuning_status.brake_flag = 0;
            tuning_status.motorctrl_status = TUNING_MOTORCTRL_OFF;
            i_position_feedback.set_config(pos_feedback_config);
            i_position_control.set_motorcontrol_config(motorcontrol_config);
        }
        break;

    //direction
    case 'd':
        pos_velocity_ctrl_config = i_position_control.get_position_velocity_control_config();
        if (pos_velocity_ctrl_config.polarity == INVERTED_POLARITY) {
            pos_velocity_ctrl_config.polarity = NORMAL_POLARITY;
        } else {
            pos_velocity_ctrl_config.polarity = INVERTED_POLARITY;
        }
        i_position_control.set_position_velocity_control_config(pos_velocity_ctrl_config);
        break;

    //sensor polarity
    case 's':
        if (!isnull(i_position_feedback)) {
            switch(tuning_status.mode_2) {
            case 's':
                //FIXME: don't use pole pairs to store sensor status
                motorcontrol_config.pole_pair = 0;
                for (int i=0; i<100; i++) {
                    int status;
                    { void , void, status } = i_position_feedback.get_real_position();
                    motorcontrol_config.pole_pair += status;
                    delay_milliseconds(1);
                }
                break;
            default:
                if (pos_feedback_config.polarity == NORMAL_POLARITY) {
                    pos_feedback_config.polarity = INVERTED_POLARITY;
                } else {
                    pos_feedback_config.polarity = NORMAL_POLARITY;
                }
                i_position_feedback.set_config(pos_feedback_config);
                break;
            }
        }
        break;

    //auto offset tuning
    case 'a':
        tuning_status.motorctrl_status = TUNING_MOTORCTRL_OFF;
        tuning_status.brake_flag = 0;
        motorcontrol_config = i_position_control.set_offset_detection_enabled();
        break;

    //set offset
    case 'o':
        tuning_status.brake_flag = 0;
        tuning_status.motorctrl_status = TUNING_MOTORCTRL_OFF;
        motorcontrol_config.commutation_angle_offset = tuning_status.value;
        i_position_control.set_motorcontrol_config(motorcontrol_config);
        printf("set offset to %d\n", tuning_status.value);
        break;

    //set brake
    case 'b':
        switch(tuning_status.mode_2) {
        case 's': //toggle special brake release
            pos_velocity_ctrl_config = i_position_control.get_position_velocity_control_config();
            pos_velocity_ctrl_config.special_brake_release = tuning_status.value;
            i_position_control.set_position_velocity_control_config(pos_velocity_ctrl_config);
            break;
        default:
            if (tuning_status.brake_flag == 0 || tuning_status.value == 1) {
                tuning_status.brake_flag = 1;
                printf("Brake released\n");
            } else {
                tuning_status.brake_flag = 0;
                printf("Brake blocking\n");
            }
            i_position_control.set_brake_status(tuning_status.brake_flag);
            break;
        } /* end mode_2 */
        break;

    //set zero position
    case 'z':
        if (!isnull(i_position_feedback)) {
            switch(tuning_status.mode_2) {
            case 'z':
                i_position_feedback.send_command(CONTELEC_CONF_NULL, 0, 0);
                break;
            default:
                i_position_feedback.send_command(CONTELEC_CONF_MTPRESET, tuning_status.value, 16);
                break;
            }
            i_position_feedback.send_command(CONTELEC_CTRL_SAVE, 0, 0);
            i_position_feedback.send_command(CONTELEC_CTRL_RESET, 0, 0);
        }
        break;

    //reverse torque
    case 'r':
        switch(tuning_status.motorctrl_status) {
        case TUNING_MOTORCTRL_TORQUE:
            downstream_control_data.torque_cmd = -downstream_control_data.torque_cmd;
            printf("Torque %d\n", downstream_control_data.torque_cmd);
            break;
        case TUNING_MOTORCTRL_VELOCITY:
            downstream_control_data.velocity_cmd = -downstream_control_data.velocity_cmd;
            printf("Velocity %d\n", downstream_control_data.velocity_cmd);
            break;
        }
        break;

    //set torque
    case '@':
        //switch to torque control mode
        if (tuning_status.motorctrl_status != TUNING_MOTORCTRL_TORQUE) {
            tuning_status.brake_flag = 1;
            tuning_status.repeat_flag = 0;
            tuning_status.motorctrl_status = TUNING_MOTORCTRL_TORQUE;
            i_position_control.enable_torque_ctrl();
            printf("switch to torque control mode\n");
        }
        //release the brake
        if (tuning_status.brake_flag == 0) {
            tuning_status.brake_flag = 1;
            i_position_control.set_brake_status(tuning_status.brake_flag);
        }
        downstream_control_data.torque_cmd = tuning_status.value;
        upstream_control_data = i_position_control.update_control_data(downstream_control_data);
        break;
    } /* main switch */
}
