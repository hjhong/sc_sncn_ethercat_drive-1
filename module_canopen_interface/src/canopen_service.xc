/**
 * @file canopen_service.xc
 * @brief CANopen service between communication channels and CANopen drive.
 * @author Synapticon GmbH <support@synapticon.com>
*/

#include <stdint.h>
#include <string.h>

#include "canod.h"
#include "co_interface.h"
#include "canod_constants.h"
#include "canopen_service.h"

[[distributable]]
#pragma ordered
void canopen_service(server interface i_co_communication i_co[n], unsigned n)
{
    pdo_values_t InOut;
    pdo_size_t pdo_buffer[PDO_BUFFER_SIZE];
    unsigned pdo_size = 0;

    int configuration_done = 0;

    printstrln("Start CANopen Service");

    while (1)
    {
        select
        {
            /* PDO */

            case i_co[int j].pdo_in_com(unsigned int size_in, pdo_size_t data_in[]):
                pdo_size = size_in;
                memcpy(pdo_buffer, data_in, pdo_size * sizeof(pdo_size_t));
                pdo_decode_buffer(pdo_buffer, InOut);
                break;

            case i_co[int j].pdo_out_com(pdo_size_t data_out[]) -> { unsigned int size_out }:
                pdo_encode_buffer(pdo_buffer, InOut);
                memcpy(data_out, pdo_buffer, pdo_size * sizeof(pdo_size_t));
                size_out = pdo_size;
                break;

            case i_co[int j].pdo_in(unsigned char pdo_number, long value):
                pdo_decode(pdo_number, value, InOut);
                break;

            case i_co[int j].pdo_out(unsigned char pdo_number) -> {long value_out}:
                long value;
                pdo_encode(pdo_number, value, InOut);
                value_out = value;
                break;

            case i_co[int j].pdo_exchange_app(pdo_values_t pdo_out) -> { pdo_values_t pdo_in, unsigned int status_out}:
                pdo_exchange(InOut, pdo_out, pdo_in);
                status_out = (pdo_size > 0) ? 1 : 0;
                pdo_size = 0;
                break;


            /* SDO */

            case i_co[int j].od_find_index(uint16_t address, uint8_t subindex) -> {int index_out}:
                    index_out = canod_find_index(address, subindex);
                    break;

            case i_co[int j].od_get_access(uint16_t index_) -> { uint8_t access}:
                    break;

            case i_co[int j].od_get_object_value(uint16_t index_) -> { uint32_t value_out, uint32_t bitlength_out, uint8_t error_out }:
                    unsigned bitlength = 0;
                    unsigned value = 0;
                    error_out = canod_get_entry(index_, value, bitlength);
                    bitlength_out = bitlength;
                    value_out = value;
                    break;

            case i_co[int j].od_set_object_value(uint16_t index_, uint32_t value) -> {uint8_t error_out }:
                    unsigned type = 0;
                    error_out = canod_set_entry(index_, value, type);
                    break;

            case i_co[int j].od_get_entry_description(uint16_t index_, uint32_t valueinfo) -> {struct _sdoinfo_entry_description desc_out, uint8_t error_out }:
                    struct _sdoinfo_entry_description desc;
                    error_out = canod_get_entry_description(index_, valueinfo, desc);
                    desc_out = desc;
                    break;

            case i_co[int j].od_get_all_list_length(uint32_t list_out[]):
                    unsigned list[5];
                    canod_get_all_list_length(list);
                    memcpy(list_out, list, 5 * sizeof(unsigned));
                    break;

            case i_co[int j].od_get_list(unsigned list_out[], unsigned size, unsigned listtype) -> {int size_out}:
                    unsigned list[100];
                    size_out = canod_get_list(list, 100, listtype);
                    memcpy(list_out, list, size_out * sizeof(unsigned));
                    break;

            case i_co[int j].od_get_object_description(struct _sdoinfo_entry_description &obj_out, unsigned index_) -> { int error }:
                    struct _sdoinfo_entry_description obj;
                    error = canod_get_object_description(obj, index_);
                    obj_out = obj;
                    break;

            case i_co[int j].od_get_data_length(uint16_t index_) -> {uint32_t len}:
                    len = canod_find_data_length(index_);

            /* Simple notification interface */

            case i_co[int j].configuration_ready(void):
                    configuration_done = 1;
                    break;

            case i_co[int j].configuration_get(void) -> { int value }:
                    value = configuration_done;
                    break;

            case i_co[int j].configuration_done(void):
                    configuration_done = 0;
                    break;
        }
    }
}