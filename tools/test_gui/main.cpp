#include "config.h"

#include <QApplication>

int main(int argc, char *argv[]) {
	QApplication app(argc, argv);
	Config config;
	config.show();
	return app.exec();
}
