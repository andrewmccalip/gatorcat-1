const gcat = @import("gatorcat");

pub const eni = gcat.ENI{
    .subdevices = &.{
        beckhoff_EK1100,
        beckhoff_EL3314,
        beckhoff_EL3048,
        beckhoff_EL2008,
        beckhoff_EL7041_1000,
    },
};

const beckhoff_EK1100 = gcat.ENI.SubDeviceConfiguration{
    .identity = .{
        .vendor_id = 0x2,
        .product_code = 0x44c2c52,
        .revision_number = 0x110000,
    },
};

const beckhoff_EL3314 = gcat.ENI.SubDeviceConfiguration{
    .identity = .{
        .vendor_id = 0x2,
        .product_code = 0xcf23052,
        .revision_number = 0x120000,
    },
    .coe_startup_parameters = &.{
        .{
            .transition = .PS,
            .direction = .write,
            .index = 0x8000,
            .subindex = 0x2,
            .complete_access = false,
            .data = &.{2},
            .timeout_us = 10_000,
        },
    },
    .inputs_bit_length = 128,
};

const beckhoff_EL3048 = gcat.ENI.SubDeviceConfiguration{
    .identity = .{
        .vendor_id = 0x2,
        .product_code = 0xbe83052,
        .revision_number = 0x130000,
    },
    .inputs_bit_length = 256,
};

const beckhoff_EL7041_1000 = gcat.ENI.SubDeviceConfiguration{
    .identity = .{
        .vendor_id = 0x2,
        .product_code = 0x1b813052,
        .revision_number = 0x1503e8,
    },
    .inputs_bit_length = 64,
    .outputs_bit_length = 64,
    .coe_startup_parameters = &.{
        .{
            .transition = .PS,
            .direction = .write,
            .index = 0x1c12, // RxPDO Assign
            .subindex = 0x0,
            .complete_access = true,
            .data = &.{ 0x03, 0x00, 0x00, 0x16, 0x02, 0x16, 0x04, 0x16 },
            .timeout_us = 10_000,
        },
        .{
            .transition = .PS,
            .direction = .write,
            .index = 0x1c13, // TxPDO Assign
            .subindex = 0x0,
            .complete_access = true,
            .data = &.{ 0x02, 0x00, 0x00, 0x1a, 0x03, 0x1a },
            .timeout_us = 10_000,
        },
    },
};

const beckhoff_EL2008 = gcat.ENI.SubDeviceConfiguration{
    .identity = .{
        .vendor_id = 0x2,
        .product_code = 0x7d83052,
        .revision_number = 0x100000,
    },
    .outputs_bit_length = 8,
};
