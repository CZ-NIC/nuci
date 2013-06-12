#ifndef CONFIG_H
#define CONFIG_H

#include <QMainWindow>

#include "ui_config.h"

class Config : public QMainWindow, private Ui::Config {
public:
	Config();
};

#endif
