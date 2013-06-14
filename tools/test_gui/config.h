#ifndef CONFIG_H
#define CONFIG_H

#include <QMainWindow>

#include "ui_config.h"

class QProcess;
class QDomDocument;
class ConfigModel;

class Config : public QMainWindow, private Ui::Config {
	Q_OBJECT;
public:
	typedef void (Config::*RpcCallback)(const QDomDocument &rpc, size_t id);
	Config();
private slots:
	void on_connectButton_clicked();
	void on_downloadButton_clicked();
	void on_removeButton_clicked();
	void on_mergeButton_clicked();
	void on_replaceButton_clicked();
	void on_createButton_clicked();
	void on_configView_clicked();
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
	size_t sendRpc(const QString &xml, RpcCallback callback = NULL);
	void configDownloaded(const QDomDocument &rpc, size_t id);
	void prepareXml(const QString &operation, bool subnodes, bool content);
	QProcess *process;
	QByteArray incoming;
	QHash<size_t, RpcCallback> rpcCallbacks;
	ConfigModel *model;
};

#endif
