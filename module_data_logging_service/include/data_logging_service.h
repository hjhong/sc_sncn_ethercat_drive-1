/**
 * @file file_service.h
 * @brief Simple flash file service to store configuration parameter
 * @author Synapticon GmbH <support@synapticon.com>
 */

#pragma once

#include <spiffs_service.h>
#include <shared_memory.h>

#define LOG_FILE_NAME "logging.txt"

#define LOG_DATA_INTERVAL 500000000


typedef interface DataLoggingInterface DataLoggingInterface;

interface DataLoggingInterface {


    [[guarded]] unsigned short log_user_command(char msg[], unsigned int timestamp);

    [[guarded]] unsigned short log_error(char msg[], unsigned int timestamp);

};

enum eLogMsgType {
    LOG_MSG_COMMAND = 0
    ,LOG_MSG_ERROR
    ,LOG_MSG_DATA
};

void data_logging_service(
        interface DataLoggingInterface server ?i_logif[n_logif],
        client SPIFFSInterface ?i_spiffs,
        client interface shared_memory_interface i_shared_memory,
        unsigned n_logif);
