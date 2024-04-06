requires 'Class::Accessor::Lite';
recommends 'DBD::mysql';
recommends 'DBD::MariaDB';
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

on develop => sub {
    requires 'Pod::Markdown::Github';
};
