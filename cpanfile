requires 'Class::Accessor::Lite';
requires 'DBD::mysql';
requires 'DBI';
requires 'File::Copy::Recursive';
requires 'File::Temp';
requires 'perl', '5.008_001';

on configure => sub {
    requires 'Module::Build::Tiny', '0.035';
};

on test => sub {
    requires 'Test::More';
    requires 'Test::SharedFork';
};
