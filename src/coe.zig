const std = @import("std");
const Timer = std.time.Timer;
const ns_per_us = std.time.ns_per_us;
const assert = std.debug.assert;

const commands = @import("commands.zig");
const nic = @import("nic.zig");
const config = @import("config.zig");
const esc = @import("esc.zig");
const telegram = @import("telegram.zig");

/// CoE Services
///
/// Ref: IEC 61158-6-12:2019 5.6.1
pub const Service = enum(u4) {
    emergency = 0x01,
    sdo_request = 0x02,
    sdo_response = 0x03,
    tx_pdo = 0x04,
    rx_pdo = 0x05,
    tx_pdo_remote_request = 0x06,
    rx_pdo_remote_request = 0x07,
    sdo_info = 0x08,
    _,
};

pub const CoEHeader = packed struct {
    number: u9 = 0,
    reserved: u3 = 0,
    service: Service,
};

pub const TransferType = enum(u1) {
    normal = 0x00,
    expedited = 0x01,
};

pub const DataSetSize = enum(u2) {
    four_octets = 0x00,
    three_octets = 0x01,
    two_octets = 0x02,
    one_octet = 0x03,
};

pub const CommandSpecifier = enum(u3) {
    download_request = 0x01,
    upload_request_or_response = 0x02,
    download_response = 0x03,
    abort_transfer_request = 0x04,
    _,
};

/// Mailbox Types
///
/// Ref: IEC 61158-4-12:2019 5.6
pub const MailboxType = enum(u4) {
    /// error
    ERR = 0x00,
    /// ADS over EtherCAT (AoE)
    AoE,
    /// Ethernet over EtherCAT (EoE)
    EoE,
    /// CAN Application Protocol over EtherCAT (CoE)
    CoE,
    /// File Access over EtherCAT (FoE)
    FoE,
    /// Servo Drive Profile over EtherCAT (SoE)
    SoE,
    /// Vendor Specfic over EtherCAT (VoE)
    VoE = 0x0f,
};

pub const MailboxErrorCode = enum(u16) {
    /// syntax of 6 octet mailbox header is wrong
    syntax = 0x01,
    /// specified mailbox protocol is not supported
    unsupported_protocol,
    /// channel field contains wrong value (a subdevice can ignore the channel field)
    invalid_channel,
    /// service in the mailbox protocol is not supported
    service_not_supported,
    /// mailbox protocl header of the mailbox protocol is wrong (without
    /// the 6 octet mailbox header)
    invalid_header,
    /// length of the recieved mailbox data is too short
    size_too_short,
    /// mailbox protocol cannot be processed because of limited resources,
    no_more_memory,
    /// length of the data is inconsistent
    invalid_size,
    /// mailbox service already in use
    service_in_work,
};

/// Mailbox Error Reply
///
/// Ref: IEC 61158-4-12:2019 5.6
pub const MailboxErrorReplyServiceData = struct {
    type: u16, // 0x01: mailbox command
    detail: MailboxErrorCode,
};

pub const StationAddress = u16;

/// Mailbox Header
///
/// Ref: IEC 61158-4-12:2019 5.6
pub const MailboxHeader = packed struct(u48) {
    /// length of mailbox service data
    length: u16,
    address: StationAddress,
    /// reserved
    channel: u6,
    /// 0: lowest priority, 3: highest priority
    priority: u2,
    /// type of mailbox communication
    type: MailboxType,
    /// counter for the mailbox services
    /// zero is reserved. 1 is start value. next value after 7 is 1.
    ///
    /// SubDevice shall increment the counter for each new mailbox service. The maindevice
    /// shall check this for detection of lost mailbox services. The maindevice shall
    /// increment the counter value before retrying and the subdevice shall check for this
    /// for detection of repeat service. The subdevice shall not check the sequence of the
    /// counter value. The maindevice and the subdevice counters are independent.
    cnt: u3,
    reserved: u1 = 0,
};

/// Mailbox
///
/// Mailbox communication data. Goes in data field of datagram.
///
/// Ref: IEC 61158-4-12:2019 5.6
pub const Mailbox = struct {
    mbx_header: MailboxHeader,
    /// mailbox service data
    data: []u8,
};

/// SDO Header for mailbox communication.
/// Common accross a couple of the mailbox schemas.
///
/// Ref: IEC 61158-6-12
pub const InitSDOHeader = packed struct {
    size_indicator: bool,
    transfer_type: TransferType,
    data_set_size: DataSetSize,
    /// false: entry addressed with index and subindex will be downloaded.
    /// true: complete object will be downlaoded. subindex shall be zero (when subindex zero
    /// is to be included) or one (subindex 0 excluded)
    complete_access: bool,
    command: CommandSpecifier,
    index: u16,
    /// shall be zero or one if complete access is true.
    subindex: u8,
};

/// SDO Download Expedited Request
///
/// Ref: IEC 61158-6-12:2019 5.6.2.1.1
pub const SDODownloadExpeditedRequest = packed struct(u128) {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_header: InitSDOHeader,
    /// un-used octets shall be zero.
    data: u32,
};

/// SDO Download Expedited Response
///
/// Ref: IEC 61158-6-12:2019 5.6.2.1.2
pub const SDODownloadExpeditedResponse = packed struct(u128) {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_header: InitSDOHeader,
    reserved: u32 = 0,
};

/// SDO Download Normal Request
///
/// Ref: IEC 61158-6-12:2019 5.6.2.2.1
pub const SDODownloadNormalRequest = struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_header: InitSDOHeader,
    complete_size: u32,
    data: []u8,
};

/// SDO Download Normal Response
///
/// Ref: IEC 61158-6-12:2019 5.6.2.2.2
pub const SDODownloadNormalResponse = SDODownloadExpeditedResponse;

pub const SegmentDataSize = enum(u3) {
    seven_octets = 0x00,
    six_octets = 0x01,
    five_octets = 0x02,
    four_octets = 0x03,
    three_octets = 0x04,
    two_octets = 0x05,
    one_octet = 0x06,
    zero_octets = 0x07,
};

/// SDO Segment Header
///
/// Ref: IEC 61158-6-12:2019 5.6.2.3.1
pub const SDOSegmentHeader = packed struct {
    more_follows: bool,
    seg_data_size: SegmentDataSize,
    /// shall toggle with every segment, starting with 0x00
    toggle: bool,
    command: CommandSpecifier,
};

/// SDO Download Seqment Request
///
/// Ref: IEC 61158-6-12:2019 5.6.2.3.1
pub const SDODownloadSegmentRequest = struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    seg_header: SDOSegmentHeader,
    data: []u8,
};

/// SDO Download Segment Response
///
/// Ref: IEC 61158-6-12:2019 5.6.2.3.2
pub const SDODownloadSegmentResponse = packed struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    seg_header: SDOSegmentHeader,
    /// 7 bytes
    reserved: u56,
};

/// SDO Upload Expedited Request
///
/// Ref: IEC 61158-6-12:2019 5.6.2.4.1
pub const SDOUploadExpeditedRequest = packed struct(u128) {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_header: InitSDOHeader,
    reserved2: u32 = 0,
};

/// SDO Upload Expedited Response
///
/// Ref: IEC 61158-6-12:2019 5.6.2.4.2
pub const SDOUploadExpeditedResponse = packed struct(u128) {
    header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_header: InitSDOHeader,
    data: u32,
};

/// SDO Upload Normal Request
///
/// Ref: IEC 61158-6-12:2019 5.6.2.5.1
pub const SDOUploadNormalRequest = SDOUploadExpeditedRequest;

/// SDO Upload Normal Response
///
/// Ref: IEC 61158-6-12:2019 5.6.2.5.2
pub const SDOUploadNormalResponse = struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_header: InitSDOHeader,
    complete_size: u23,
    data: []u8,
};

/// SDO Upload Segment Request
///
/// Ref: IEC 61158-6-12:2019 5.6.2.6.1
pub const SDOUploadSegmentRequest = packed struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    seg_header: SDOSegmentHeader,
    /// 7 bytes
    reserved: u56 = 0,
};

/// SDO Upload Segment Response
///
/// Ref: IEC 61158-6-12:2019 5.6.2.6.2
pub const SDOUploadSegmentResponse = struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    seg_header: SDOSegmentHeader,
    data: []u8,
};

/// SDO Abort Codes
///
/// Ref: IEC 61158-6-12:2019 5.6.2.7.2
pub const SDOAbortCode = enum(u32) {
    ToggleBitNotChanged = 0x05_03_00_00,
    SdoProtocolTimeout = 0x05_04_00_00,
    ClientServerCommandSpecifierNotValidOrUnknown = 0x05_04_00_01,
    OutOfMemory = 0x05_04_00_05,
    UnsupportedAccessToAnObject = 0x06_01_00_00,
    AttemptToReadToAWriteOnlyObject = 0x06_01_00_01,
    AttemptToWriteToAReadOnlyObject = 0x06_01_00_02,
    SubindexCannotBeWritten = 0x06_01_00_03,
    SdoCompleteAccessNotSupportedForVariableLengthObjects = 0x06_01_00_04,
    ObjectLengthExceedsMailboxSize = 0x06_01_00_05,
    ObjectMappedToRxPdoSdoDownloadBlocked = 0x06_01_00_06,
    ObjectDoesNotExistInObjectDirectory = 0x06_02_00_00,
    ObjectCannotBeMappedIntoPdo = 0x06_04_00_41,
    NumberAndLengthOfObjectsExceedsPdoLength = 0x06_04_00_42,
    GeneralParameterIncompatibilityReason = 0x06_04_00_43,
    GeneralInternalIncompatibilityInDevice = 0x06_04_00_47,
    AccessFailedDueToHardwareError = 0x06_06_00_00,
    DataTypeMismatchLengthOfServiceParameterDoesNotMatch = 0x06_07_00_10,
    DataTypeMismatchLengthOfServiceParameterTooHigh = 0x06_07_00_12,
    DataTypeMismatchLengthOfServiceParameterTooLow = 0x06_07_00_13,
    SubindexDoesNotExist = 0x06_09_00_11,
    ValueRangeOfParameterExceeded = 0x06_09_00_30,
    ValueOfParameterWrittenTooHigh = 0x06_09_00_31,
    ValueOfParameterWrittenTooLow = 0x06_09_00_32,
    MaximumValueLessThanMinimumValue = 0x06_09_00_36,
    GeneralError = 0x08_00_00_00,
    DataCannotBeTransferredOrStoredToApplication = 0x08_00_00_20,
    DataCannotBeTransferredOrStoredDueToLocalControl = 0x08_00_00_21,
    DataCannotBeTransferredOrStoredDueToESMState = 0x08_00_00_22,
    ObjectDictionaryDynamicGenerationFailedOrNoObjectDictionaryPresent = 0x08_00_00_23,
};

/// Abort SDO Transfer Request
///
/// Ref: IEC 61158-6-12:2019 5.6.2.7.1
pub const AbortSDOTransferRequest = packed struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_header: InitSDOHeader,
    abort_code: SDOAbortCode,
};

/// SDO Info Op Codes
///
/// Ref: IEC 61158-6-12:2019 5.6.3.2
pub const SDOInfoOpCode = enum(u7) {
    get_od_list_request = 0x01,
    get_od_list_respoonse = 0x02,
    get_object_description_request = 0x03,
    get_object_description_response = 0x04,
    get_entry_description_request = 0x05,
    get_entry_description_response = 0x06,
    sdo_info_error_request = 0x07,
};

/// SDO Info Header
///
/// Ref: IEC 61158-6-12:2019 5.6.3.2
pub const SDOInfoHeader = packed struct {
    opcode: SDOInfoOpCode,
    incomplete: bool,
    reserved: u8 = 0,
    fragments_left: u16,
};

/// OD List Types
///
/// Ref: IEC 61158-6-12:2019 5.6.3.3.1
pub const ODListType = enum(u16) {
    num_object_in_5_lists = 0x00,
    all_objects = 0x01,
    rxpdo_mappable = 0x02,
    txpdo_mappable = 0x03,
    device_replacement_stored = 0x04, // what does this mean?
    startup_parameters = 0x05,
};

/// Get OD List Request
///
/// Ref: IEC 61158-6-12:2019 5.6.3.3.1
pub const GetODListReqest = packed struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_info_header: SDOInfoHeader,
    list_type: ODListType,
};

/// Get OD List Response
///
/// Ref: IEC 61158-6-12:2019 5.6.3.3.2
pub const GetODListResponse = struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_info_header: SDOInfoHeader,
    list_type: ODListType,
    index_list: []u16,
};

/// Get Object Description Request
///
/// Ref: IEC 61158-6-12:2019 5.6.3.5.1
pub const GetObjectDescriptionRequest = packed struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_info_header: SDOInfoHeader,
    index: u16,
};

/// Object Code
///
/// Ref: IEC 61158-6-12:2019 5.6.3.5.2
pub const ObjectCode = enum(u8) {
    variable = 7,
    array = 8,
    record = 9,
    _,
};

/// Get Object Description Response
///
/// Ref: IEC 61158-6-12:2019 5.6.3.5.2
pub const GetObjectDescriptionResponse = struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_info_header: SDOInfoHeader,
    index: u16,
    data_type: u16,
    max_subindex: u8,
    object_code: ObjectCode,
    name: []u8,
};

/// Value Info
///
/// What info about the value will be included in the response.
///
/// Ref: IEC 61158-6-12:2019 5.6.3.6.1
pub const ValueInfo = packed struct(u8) {
    reserved: u3 = 0,
    unit_type: bool,
    default_value: bool,
    minimum_value: bool,
    maximum_value: bool,
    reserved2: u1 = 0,
};

/// Get Entry Description Request
///
/// Ref: IEC 61158-6-12:2019 5.6.3.6.1
pub const GetEntryDescriptionRequest = packed struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_info_header: SDOInfoHeader,
    index: u16,
    subindex: u8,
    value_info: ValueInfo,
};

/// Object Access
///
/// Ref: IEC 61158-6-12:2019 5.6.3.2
pub const ObjectAccess = packed struct(u16) {
    read_PREOP: bool,
    read_SAFEOP: bool,
    read_OP: bool,
    write_PREOP: bool,
    write_SAFEOP: bool,
    write_OP: bool,
    rxpdo_mappable: bool,
    txpdo_mappable: bool,
    backup: bool,
    setting: bool,
    reserved: u6 = 0,
};

/// Get Entry Description Response
///
/// Ref: IEC 61158-6-12:2019 5.6.3.2
pub const GetEntryDescriptionResponse = struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_info_header: SDOInfoHeader,
    index: u16,
    subindex: u8,
    value_info: ValueInfo,
    data_type: u16,
    bit_length: u16,
    object_access: ObjectAccess,
    data: []u8,
};

/// SDO Info Error Request
///
/// Ref: IEC 61158-6-12:2019 5.6.3.8
pub const SDOInfoErrorRequest = packed struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    sdo_info_header: SDOInfoHeader,
    abort_code: SDOAbortCode,
};

/// Emergency Request
///
/// Ref: IEC 61158-6-12:2019 5.6.4.1
pub const EmergencyRequest = struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    error_code: u16,
    error_register: u8,
    data: u40,
    reserved: []u8,
};

/// RxPDO Mailbox Transmission
///
/// Ref: IEC 61158-6-12:2019 5.6.5.1
pub const RxPDOTransmission = struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
    data: []u8,
};

/// TxPDO Mailbox Transmission
///
/// Ref: IEC 61158-6-12:2019 5.6.5.1
pub const TxPDOTransmission = RxPDOTransmission;

/// RxPDO Remote Transmission Request
///
/// Ref: IEC 61158-6-12:2019 5.6.5.3
pub const RxPDORemoteTransmissionRequest = packed struct {
    mbx_header: MailboxHeader,
    coe_header: CoEHeader,
};

/// TxPDO Remote Transmission Request
///
/// Ref: IEC 61158-6-12:2019 5.6.5.4
pub const TxPDORemoteTransmissionRequest = RxPDORemoteTransmissionRequest;

pub const CommandStatus = enum(u8) {
    completed_no_errors_no_reply = 0,
    completed_no_errors_reply = 1,
    complete_error_no_reply = 2,
    complete_error_reply = 3,
    executing = 255,
    _,
};

/// Command Object Structure
///
/// Each command shall have data type 0x0025.
///
/// Ref: IEC 61158-6-12:2019 5.6.6
pub const Command = struct {
    n_entries: u8,
    command: []u8,
    status: u8,
    reply: []u8,
};

/// The maximum mailbox size is limited by the maximum data that can be
/// read by a single datagram.
pub const max_mailbox_size = 1486;
comptime {
    assert(max_mailbox_size == telegram.max_frame_length - // 1514
        @divExact(@bitSizeOf(telegram.EthernetHeader), 8) - // u112
        @divExact(@bitSizeOf(telegram.EtherCATHeader), 8) - // u16
        @divExact(@bitSizeOf(telegram.DatagramHeader), 8) - // u80
        @divExact(@bitSizeOf(u16), 8)); // wkc
}

pub fn sdoReadExpedited(
    port: *nic.Port,
    station_address: u16,
    index: u16,
    subindex: u8,
    retries: u32,
    recv_timeout_us: u32,
    mbx_timeout_us: u32,
) !void {
    _ = mbx_timeout_us;
    _ = index;
    _ = subindex;

    // If mailbox in has got something in it, read mailbox to wipe it.
    const mbx_in: esc.SyncManagerAttributes = blk: {
        for (0..retries +% 1) |_| {
            const sm1_res = try commands.FPRD_ps(
                port,
                esc.SyncManagerAttributes,
                .{
                    .station_address = station_address,
                    .offset = @intFromEnum(esc.RegisterMap.SM1),
                },
                recv_timeout_us,
            );
            if (sm1_res.wkc == 1) {
                std.log.info("sm1 status: {}", .{sm1_res.ps.status});
                break :blk sm1_res.ps;
            }
        } else {
            return error.SubDeviceUnresponsive;
        }
        unreachable;
    };
    // mailbox configured?
    if (mbx_in.length == 0 or mbx_in.length > max_mailbox_size) {
        return error.InvalidMailboxConfiguration;
    }

    if (mbx_in.status.mailbox_full) {
        var buf = std.mem.zeroes([max_mailbox_size]u8); // yeet!
        for (0..retries +% 1) |_| {
            const wkc = try commands.FPRD(
                port,
                .{
                    .station_address = station_address,
                    .offset = mbx_in.physical_start_address,
                },
                &buf,
                recv_timeout_us,
            );
            if (wkc == 1) {
                break;
            }
        } else {
            return error.SubDeviceUnresponsive;
        }
    }

    const mbx_out: esc.SyncManagerAttributes = blk: {
        for (0..retries +% 1) |_| {
            const sm0_res = try commands.FPRD_ps(
                port,
                esc.SyncManagerAttributes,
                .{
                    .station_address = station_address,
                    .offset = @intFromEnum(esc.RegisterMap.SM0),
                },
                recv_timeout_us,
            );
            if (sm0_res.wkc == 1) {
                std.log.info("sm1 status: {}", .{sm0_res.ps.status});
                break :blk sm0_res.ps;
            }
        } else {
            return error.SubDeviceUnresponsive;
        }
        unreachable;
    };
    // mailbox configured?
    if (mbx_out.length == 0 or mbx_out.length > max_mailbox_size) {
        return error.InvalidMailboxConfiguration;
    }
}

pub fn readMailbox(
    port: *nic.Port,
    station_address: u16,
    retries: u32,
    recv_timeout_us: u32,
    mbx_timeout_us: u32,
) !void {
    _ = retries;
    var timer = try Timer.start();

    const mbx_in: esc.SyncManagerAttributes = blk: {
        while (timer.read() < mbx_timeout_us * ns_per_us) {
            const sm1_res = try commands.FPRD_ps(
                port,
                esc.SyncManagerAttributes,
                .{
                    .station_address = station_address,
                    .offset = @intFromEnum(esc.RegisterMap.SM1),
                },
                recv_timeout_us,
            );
            if (sm1_res.wkc == 1) {
                if (sm1_res.ps.status.mailbox_full) {
                    break :blk sm1_res.ps;
                }
            }
        } else {
            return error.Timeout;
        }
    };
    assert(mbx_in.status.mailbox_full);

    // mailbox configured?
    if (mbx_in.length == 0 or mbx_in.length > max_mailbox_size) {
        return error.InvalidMailboxConfiguration;
    }
}

// fn deserializeMailboxData()

// fn readMailbox(port: *nic.Port) !void {
//     var buf = std.mem.zeroes([1486]u8); // yeet!
//     // read raw mailbox data into the buffer
//     read(port, &buf);
//     _ = deserializeMialboxData(&buf);
// }
