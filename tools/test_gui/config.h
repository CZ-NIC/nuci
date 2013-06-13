#ifndef CONFIG_H
#define CONFIG_H

#include <QMainWindow>

#include "ui_config.h"

class QProcess;
class QDomDocument;

class Config : public QMainWindow, private Ui::Config {
	Q_OBJECT;
public:
	Config();
private slots:
	void on_connectButton_clicked();
	void data();
	void terminated();
private:
	void connectNuci();
	void disconnectNuci();
	void sendData(const QString &data);
	void writeData(QByteArray &data);
	void handleMessage(const QByteArray &data);
	void handleHello(const QDomDocument &hello);
	void handleRpc(const QDomDocument &rpc);
	void sendRpc(const QString &xml);
	QProcess *process;
	QByteArray incoming;
};

#endif
